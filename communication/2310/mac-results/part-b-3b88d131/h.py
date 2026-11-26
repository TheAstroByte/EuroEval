"""Run one isolated command with independent safety sampling and footprint collection."""
import concurrent.futures
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import time

run = Path(os.environ['RUN'])
name = sys.argv[1]
command = sys.argv[2:]
if not command:
    raise SystemExit('Missing command')
if (run / f'{name}.result.json').exists():
    raise SystemExit(f'Result already exists for {name}; preserve it')


def mem():
    """Read host memory and pressure without performing any footprint work."""
    pressure = int(subprocess.check_output(['sysctl', '-n', 'kern.memorystatus_vm_pressure_level'], text=True, timeout=5))
    vm = subprocess.check_output(['vm_stat'], text=True, timeout=5)
    page = int(re.search(r'page size of (\d+) bytes', vm)[1])
    pages = lambda key: int(re.search(rf'Pages {key}:\s+(\d+)', vm)[1])
    swap = subprocess.check_output(['sysctl', '-n', 'vm.swapusage'], text=True, timeout=5)
    return {'t': time.time(), 'available': (pages('free') + pages('inactive')) * page,
            'swap_mib': float(re.search(r'used = ([\d.]+)M', swap)[1]), 'pressure': pressure}


def owned(pgid):
    """Return members of the command's dedicated process group."""
    if pgid is None:
        return []
    result = subprocess.run(['pgrep', '-g', str(pgid)], capture_output=True, text=True, timeout=5)
    if result.returncode not in (0, 1):
        raise RuntimeError(f'pgrep returned {result.returncode}')
    return [int(value) for value in result.stdout.split()]


def footprint(pgid, sample_index):
    """Collect at most six bounded snapshots outside the safety loop."""
    snapshot = {'sample_index': sample_index, 'started_at': time.time(), 'pids': owned(pgid), 'captures': []}
    for pid in snapshot['pids'][:6]:
        path = run / f'{name}.footprint-{sample_index}-{pid}.txt'
        try:
            result = subprocess.run(['footprint', '-f', 'bytes', '-p', str(pid)], capture_output=True, text=True, timeout=3)
            path.write_text(result.stdout + result.stderr)
            match = re.search(r'Footprint:\s+(\d+) B', result.stdout)
            snapshot['captures'].append({'pid': pid, 'bytes': int(match[1]) if match else None, 'exit': result.returncode, 'file': path.name})
        except subprocess.TimeoutExpired:
            snapshot['captures'].append({'pid': pid, 'timeout': True})
    snapshot['ended_at'] = time.time()
    snapshot['footprint_mib'] = sum(row.get('bytes') or 0 for row in snapshot['captures']) / 2**20
    return snapshot


def guard(sample, baseline):
    """Return the first safety-stop condition, if present."""
    if sample['pressure'] >= 4:
        return 'pressure 4'
    if sample['swap_mib'] - baseline['swap_mib'] > 1024:
        return 'swap growth > 1 GiB'
    return None


reason = None


def on_signal(signum, frame):
    """Record operator cancellation for the main loop and final cleanup."""
    global reason
    reason = reason or f'operator signal {signum}'


for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
    signal.signal(sig, on_signal)

base = mem()
samples = [base]
footprints = []
escalations = []
process = None
pgid = None
executor = concurrent.futures.ThreadPoolExecutor(max_workers=1)
future = None
error = None
started = time.time()
child_env = dict(os.environ)
legacy_fraction_was_present = 'VLLM_METAL_MEMORY_FRACTION' in child_env
child_env.pop('VLLM_METAL_MEMORY_FRACTION', None)


def stop_group():
    """Reap the root and escalate only inside the owned process group."""
    if pgid is None:
        return
    assert pgid != os.getpgrp()
    for sig, duration in ((signal.SIGINT, 30), (signal.SIGTERM, 10), (signal.SIGKILL, 5)):
        process.poll()
        if not owned(pgid):
            return
        escalations.append({'signal': sig.name, 't': time.time(), 'pids': owned(pgid)})
        try:
            os.killpg(pgid, sig)
        except ProcessLookupError:
            return
        deadline = time.monotonic() + duration
        while time.monotonic() < deadline:
            process.poll()
            if not owned(pgid):
                return
            time.sleep(.2)


try:
    if base['pressure'] >= 2:
        reason = f'refusing to start: baseline pressure {base["pressure"]}'
    else:
        log = (run / f'{name}.log').open('w')
        process = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT, start_new_session=True, env=child_env)
        pgid = process.pid
        (run / f'{name}.start').write_text(json.dumps({'cmd': command, 'pgid': pgid, 'harness_pid': os.getpid(), 'baseline': base, 'started_at': started, 'legacy_fraction_removed_if_present': legacy_fraction_was_present}, indent=2) + '\n')
        print(json.dumps({'name': name, 'harness_pid': os.getpid(), 'pgid': pgid, 'baseline': base}), flush=True)
        next_sample = time.monotonic() + 2
        index = 0
        while process.poll() is None and reason is None:
            time.sleep(max(0, next_sample - time.monotonic()))
            if reason is not None:
                break
            sample = mem()
            samples.append(sample)
            index += 1
            reason = reason or guard(sample, base)
            # Safety is evaluated before scheduling or consuming footprint work.
            if reason is not None:
                break
            if time.time() - started > float(os.environ.get('MAX_RUN_SECONDS', '3600')):
                reason = 'run time limit exceeded'
                break
            if future is not None and future.done():
                footprints.append(future.result())
                future = None
            if index % 8 == 0 and future is None:
                future = executor.submit(footprint, pgid, index)
            next_sample += 2
            if next_sample < time.monotonic():
                next_sample = time.monotonic() + 2
except Exception as exc:
    error = f'{type(exc).__name__}: {exc}'
    reason = reason or 'harness error'
finally:
    stop_group()
    if process is not None:
        process.poll()
        log.close()
    if future is not None:
        try:
            footprints.append(future.result(timeout=22))
        except Exception as exc:
            footprints.append({'error': f'{type(exc).__name__}: {exc}'})
    executor.shutdown(wait=True)
    result = {'exit': process.returncode if process else None, 'stop_reason': reason, 'leftover_owned_pids': owned(pgid),
              'peak_pressure': max(row['pressure'] for row in samples),
              'swap_delta_mib': max(row['swap_mib'] for row in samples) - base['swap_mib'],
              'min_available_gib': min(row['available'] for row in samples) / 2**30,
              'peak_footprint_mib': max([row.get('footprint_mib', 0) for row in footprints] or [0]),
              'started_at': started, 'ended_at': time.time(), 'harness_error': error,
              'cleanup_signals': escalations, 'footprints_are_independent': True}
    (run / f'{name}.samples.json').write_text(json.dumps(samples) + '\n')
    (run / f'{name}.footprints.json').write_text(json.dumps(footprints, indent=2) + '\n')
    (run / f'{name}.result.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result), flush=True)
