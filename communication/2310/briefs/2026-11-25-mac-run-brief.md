# EuroEval #2310 Mac run brief (64 GB Mac)

**For the agent running this.** Your job is to test a branch on Apple Silicon. You do
not write features. The implementation machine can't run Metal, so it pushes
`feat/2310-apple-gpu-worker` to the fork `https://github.com/TheAstroByte/EuroEval`.

- **Plan:** `2026-11-24-euroeval-2310-implementation.md`. Read it for context.
- **Issue:** https://github.com/EuroEval/EuroEval/issues/2310, written by Dan
  (`saattrupdan`), the main maintainer.

The operator tells you which part to run:

- **Part A: Gate A.** Runs after push 1, which contains only the Darwin pin bump. No
  broker is involved.
- **Part B: worker acceptance.** Runs after push 2, which has the worker changes and has
  passed Gate A. It runs against the **current production broker**.
  - The broker changes (provenance 3, eligibility 4a, declines 4b) are not deployed until
    Dan merges and deploys. Record those rows as **pending deploy**, not as passed.
  - The worker's optional `supported_architectures` field is ignored by today's broker.
    That is safe.

## Rules

1. **Code changes.** Change code only where a step says so. Commit on the branch, then
   stop. A push to the fork needs a Sol PASS on the diff, run from the implementation
   machine, **and** the operator's approval.
2. **Memory.** `u` is the inference fraction passed as `--gpu-memory-utilization` to
   direct `euroeval` runs. It is never the CLI default 0.8.
   - Never set `VLLM_METAL_MEMORY_FRACTION`.
   - The worker in Part B keeps its default offer factor of 0.8. The worker turns that
     into `u` itself (`runtime.py:659`), so do **not** pass `u` to `euroeval-worker`.
     That would apply the scaling twice.
3. **Stop conditions.**
   - The harness refuses to start when the baseline pressure is already ≥ 2.
   - It checks every 2 s sample **before** any footprint work, and stops at the first
     sample with pressure 4, or with swap more than 1 GiB above that run's baseline.
   - Footprint calls are capped at 3 s each. Record every stop.
   - The **pass** criterion is stricter than the stop condition: no swap growth beyond
     noise, which is ≤ 256 MiB, as in the plan.
4. **Stopping a run yourself.** Press Ctrl-C in the harness terminal, or send
   `kill -INT` to the harness PID. The harness stops the run's whole process group,
   escalating from INT to TERM to KILL until no owned process is left. It still writes
   the result files.
5. **Posting.** Post issue comments only after the operator approves the text.
6. **Live broker.** `euroeval-worker` runs against the live broker in Part B only.
7. **Shell.** Run every block in `bash`.
8. **Step 0 scripts.** Do not reuse them. They hardcode the old checkout and old memory
   controls. Use the harness below.

## Setup (both parts)

**Fresh clone and install.** This is the contributor install path, so Part B's
"`make install`" acceptance row reuses this:

```bash
cd ~/Developer
rm -rf EuroEval-2310
git clone https://github.com/TheAstroByte/EuroEval.git EuroEval-2310
cd EuroEval-2310
git checkout feat/2310-apple-gpu-worker
git log --oneline -3
time make install
```

Answer each `.env` prompt with Enter, then record the versions and the cap:

```bash
uv run python -c "import importlib.metadata as m; [print(p, m.version(p)) for p in ('euroeval','vllm','vllm-metal','mlx')]"
uv run python -c "import mlx.core as mx; print(mx.device_info()['max_recommended_working_set_size'])"
```

- **Install failure:** if `make install` fails, record the error.
- **Lock failure:** if the lock cannot resolve on macOS, run `uv lock`, commit `uv.lock`
  per rule 1, and report it.

**Harness.** Create `RUN=/tmp/ee-2310-gateA` for Part A or `RUN=/tmp/ee-2310-accept` for
Part B, then write `$RUN/h.py`:

```bash
mkdir -p $RUN
cat > $RUN/h.py <<'PY'
"""Run one command in its own process group, sample memory, stop on guards, always clean up."""
import json, os, re, signal, subprocess, sys, time
from pathlib import Path
run = Path(os.environ["RUN"]); name = sys.argv[1]; cmd = sys.argv[2:]
def mem():
    vm = subprocess.check_output(["vm_stat"], text=True, timeout=5)
    page = int(re.search(r"page size of (\d+) bytes", vm)[1])
    pages = lambda k: int(re.search(rf"Pages {k}:\s+(\d+)", vm)[1])
    swap = subprocess.check_output(["sysctl", "-n", "vm.swapusage"], text=True, timeout=5)
    pressure = int(subprocess.check_output(["sysctl", "-n", "kern.memorystatus_vm_pressure_level"], text=True, timeout=5))
    return {"t": time.time(), "available": (pages("free") + pages("inactive")) * page,
            "swap_mib": float(re.search(r"used = ([\d.]+)M", swap)[1]), "pressure": pressure}
def owned(pgid):
    r = subprocess.run(["pgrep", "-g", str(pgid)], capture_output=True, text=True, timeout=5)
    return [int(x) for x in r.stdout.split()]
def footprint(pids):
    total = 0.0
    for pid in pids[:6]:
        try: r = subprocess.run(["footprint", "-p", str(pid)], capture_output=True, text=True, timeout=3).stdout
        except subprocess.TimeoutExpired: continue
        m = re.search(r"Footprint:\s+([\d.]+)\s*(KB|MB|GB)", r)
        if m: total += float(m[1]) * {"KB": 1 / 1024, "MB": 1, "GB": 1024}[m[2]]
    return total
def guard(s, base):
    if s["pressure"] >= 4: return "pressure 4"
    if s["swap_mib"] - base["swap_mib"] > 1024: return "swap growth > 1 GiB"
    return None
def stop_group(pgid):
    for sig, wait in ((signal.SIGINT, 30), (signal.SIGTERM, 10), (signal.SIGKILL, 5)):
        if not owned(pgid): return
        try: os.killpg(pgid, sig)
        except ProcessLookupError: return
        end = time.time() + wait
        while time.time() < end and owned(pgid): time.sleep(1)
base = mem()
if guard(base, base) or base["pressure"] >= 2:
    sys.exit(f"refusing to start: baseline pressure {base['pressure']}; close applications and retry")
samples, reason = [base], None
log = open(run / f"{name}.log", "w")
p = subprocess.Popen(cmd, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
pgid = p.pid
(run / f"{name}.start").write_text(json.dumps({"cmd": cmd, "pgid": pgid, "baseline": base}))
def on_signal(signum, frame):
    global reason; reason = reason or f"operator signal {signum}"
signal.signal(signal.SIGINT, on_signal); signal.signal(signal.SIGTERM, on_signal)
signal.signal(signal.SIGHUP, on_signal)
i = 0
try:
    while p.poll() is None and reason is None:
        time.sleep(2); s = mem(); samples.append(s); i += 1
        reason = reason or guard(s, base)
        if reason is None and i % 8 == 0:
            s["pids"] = owned(pgid); s["footprint_mib"] = footprint(s["pids"])
finally:
    stop_group(pgid)
    p.poll()
    res = {"exit": p.returncode, "stop_reason": reason, "leftover_owned_pids": owned(pgid),
           "peak_pressure": max(x["pressure"] for x in samples),
           "swap_delta_mib": max(x["swap_mib"] for x in samples) - base["swap_mib"],
           "min_available_gib": min(x["available"] for x in samples) / 2**30,
           "peak_footprint_mib": max([x.get("footprint_mib", 0.0) for x in samples])}
    (run / f"{name}.samples.json").write_text(json.dumps(samples))
    (run / f"{name}.result.json").write_text(json.dumps(res, indent=2))
    print(json.dumps(res))
PY
export RUN
EE="uv run euroeval --evaluate-val-split --force --no-save-results --raise-errors --requires-safetensors --verbose"
```

`$EE` is used only as `python3 $RUN/h.py <name> $EE …`. Bash splits it into separate
arguments, which is why every block runs in `bash`.

**Compute `u` once**, from a fresh idle snapshot with heavy applications closed. Persist
it and reuse it everywhere:

```bash
uv run python - <<'PY' > $RUN/u.json
import json, re, subprocess, mlx.core as mx
vm = subprocess.check_output(["vm_stat"], text=True)
page = int(re.search(r"page size of (\d+) bytes", vm)[1])
avail = sum(int(re.search(rf"Pages {k}:\s+(\d+)", vm)[1]) for k in ("free", "inactive")) * page
cap = int(mx.device_info()["max_recommended_working_set_size"])
usable = min(cap, max(0, avail - 2**30))
print(json.dumps({"available": avail, "cap": cap, "usable": usable, "u": round(0.8 * usable / cap, 4)}))
PY
U=$(python3 -c "import json;print(json.load(open('$RUN/u.json'))['u'])"); echo "u=$U"
python3 -c "import sys; u=float('$U'); sys.exit(0 if 0.05 < u <= 0.8 else 1)" || { echo "u out of range; stop and report"; exit 1; }
```

**Schema auditor**, used in A3:

```bash
cat > $RUN/audit.py <<'PY'
import json, re, sys
from jsonschema import Draft202012Validator
log, cache = sys.argv[1], sys.argv[2]
schema = json.loads(re.search(r"Using structured generation with the JSON schema: (.*)", open(log).read())[1])
v = Draft202012Validator(schema); rows = json.load(open(cache))
c = {"unique": len(rows), "invalid_json": 0, "schema_violation": 0}
for r in rows.values():
    try: x = json.loads(r["sequence"])
    except json.JSONDecodeError: c["invalid_json"] += 1; continue
    if list(v.iter_errors(x)): c["schema_violation"] += 1
print(json.dumps(c))
PY
```

## Part A: Gate A

The model is `M="Qwen/Qwen3-0.6B#no-thinking"`. Every command runs from
`~/Developer/EuroEval-2310`.

1. **Memory control.** Run:

   ```bash
   python3 $RUN/h.py a1-memory $EE --model "$M" --dataset sst5 --num-iterations 1 --gpu-memory-utilization $U
   grep -h "Paged attention" $RUN/a1-memory.log
   ```

   - **Pass:** the log reports `--gpu-memory-utilization=<u>` and a `metal_limit` equal to
     the cap. In the result JSON, the exit is 0, `stop_reason` is null, peak pressure is
     ≤ 2, and the swap delta is ≤ 256 MiB.
   - **Fail:** stop Part A and report.
2. **Features at `u`** (10 iterations, both shot modes, run one dataset at a time):

   ```bash
   for d in sst5 hellaswag; do python3 $RUN/h.py a2-$d $EE --model "$M" --dataset $d --gpu-memory-utilization $U; done
   grep -cE "fall back to extracting the labels using word edit distance" $RUN/a2-sst5.log $RUN/a2-hellaswag.log
   grep -lE "Using logprobs as evaluation strategy" $RUN/a2-sst5.log $RUN/a2-hellaswag.log
   grep -lE "Using structured generation" $RUN/a2-sst5.log $RUN/a2-hellaswag.log
   ```

   - **Pass:** both runs exit 0 with `stop_reason` null; the fallback count is 0 for each log;
     both log files are listed by each of the other two greps.
3. **CoNLL with a per-shot-mode schema audit.** Run each shot mode separately with
   `--debug`. In debug mode EuroEval keeps the complete completion cache in the current
   directory and does not delete it (`generation.py:452-476,532`). The `/` in the name
   becomes `--` (`model_cache.py:72`):

   ```bash
   F=./Qwen--Qwen3-0.6B-no-thinking-conll-en-model-outputs.json
   for mode in zero-shot few-shot; do
     rm -f "$F"
     python3 $RUN/h.py a3-conll-$mode $EE --debug --model "$M" --dataset conll-en --$mode --gpu-memory-utilization $U
     cp "$F" $RUN/conll-$mode.json
     uv run python $RUN/audit.py $RUN/a3-conll-$mode.log $RUN/conll-$mode.json | tee $RUN/a3-audit-$mode.json
   done
   ```

   - **Pass, for each mode:** the run exits 0 with `stop_reason` null; the cache file
     parses as JSON; `unique > 0`, `invalid_json == 0` and `schema_violation == 0`.
   - **Missing or unparseable cache:** that mode is **unproven**. Debug runs also write
     extra files to the current directory; leave them for the archive.

4. **Regression at `u`:**

   ```bash
   for d in squad cnn-dailymail; do python3 $RUN/h.py a4-$d $EE --model "$M" --dataset $d --gpu-memory-utilization $U; done
   python3 $RUN/h.py a4-canary $EE --model "$M" --task contamination-detection --language en --gpu-memory-utilization $U
   python3 $RUN/h.py a4-switch $EE --model "$M" --model HuggingFaceTB/SmolLM2-360M-Instruct --dataset sst5 --num-iterations 1 --gpu-memory-utilization $U
   grep -h "Contamination canary" $RUN/a4-canary.log
   ```

   - **Pass:** SQuAD and CNN/DailyMail exit 0 with no failed instances. The canary shows
     `status=collected, count=256`. The switch log shows both models loaded and scored,
     and its samples show a footprint drop between them.
   - **Ctrl-C test:**
     - In a second terminal, run
       `python3 $RUN/h.py a4-interrupt $EE --model "$M" --dataset cnn-dailymail --gpu-memory-utilization $U`
       in the foreground.
     - Once `a4-interrupt.log` shows generation progress, press **Ctrl-C in that
       terminal**, as in rule 4. Do not signal the child's process group directly,
       because that bypasses the harness's stop handling.
     - **Pass:** `stop_reason` is `"operator signal 2"` and `leftover_owned_pids` is empty
       in `a4-interrupt.result.json`.
5. **If 1 passes but 2 or 3 fails.** Follow the plan's "If Gate A fails" branch:
   - build a reduced `LLM.generate` reproduction that keeps the failing run's batch size,
     sampling settings and prompts;
   - report the result;
   - **draft** any upstream issue, but do not file it;
   - do not fix code here. If the reproduction positively localises the cause in EuroEval's
     `vllm.py`, report the location. The fix is made on the implementation machine, as
     the plan says.

## Part B: worker acceptance (production broker, worker side)

Use a dedicated state directory, so that a separate credential is used:
`S=~/.euroeval-worker-2310`. Start `sleep 86400 &` first and record its PID as
`UNRELATED`.

The state probe below prints a redacted summary. It shows whether a credential exists,
but never its value. `last-submission.json` stays after the worker finishes. The broker
sets the submission ID to the lease ID (`finalise.ts:172`), so it is durable completion
evidence for a lease. `active-lease.json` is deleted right after finalisation
(`runtime.py:722-726`).

```bash
cat > $RUN/probe.py <<'PY'
import json, sys, time
from pathlib import Path
d = Path(sys.argv[1]); out = {"t": time.time()}
s = d / "state.json"
out["credential_present"] = s.exists() and bool(json.loads(s.read_text()).get("credential"))
a = d / "active-lease.json"
if a.exists():
    v = json.loads(a.read_text())
    out["lease_id"] = v["lease"]["lease_id"]; out["model"] = v["lease"]["model_id"]
    out["records"] = [{"digest": r["digest"], "acknowledged": r["acknowledged"]} for r in v.get("records", [])]
    out["finalised_submission_id"] = v.get("finalised_submission_id")
l = d / "last-submission.json"
out["last_submission_id"] = json.loads(l.read_text())["submission_id"] if l.exists() else None
print(json.dumps(out))
PY
```

1. **Hardware report.** Run
   `uv run python -c "from euroeval_worker.hardware import discover_hardware as d; print(d())"`.
   - **Pass:** there is one GPU, `metal-0`; `total` equals the cap in `u.json`; `free`
     equals `min(cap, available − 1 GiB)` within 2%; it runs without `nvidia-smi`.
2. **Auth and two leases.** Run:

   ```bash
   python3 $RUN/h.py b2-worker uv run euroeval-worker --state-dir $S
   ```

   - Complete device-flow auth.
   - **Pass:** the log shows `MLX device set to: Device(gpu, 0)`, and at least two leases
     from **different** models are finalised.
   - Between the leases, run `probe.py` and record the lease IDs.
   - The samples must show a footprint drop between the leases.
   - Once two leases are finalised, stop it with Ctrl-C in the harness terminal (rule 4).
     That stops the worker's whole process group, so it cannot keep claiming work.
3. **Task-group coverage.** From the worker log and the finalised records:
   - Map each record's dataset to its task group in `api/worker/scope-policy.json` for
     the leased language.
   - Every task group in that scope needs at least one record across the leases. Any
     group with no record is **unproven**, which can happen because coverage narrows
     leases to missing identities.
   - The worker runs EuroEval with `verbose=False` (`evaluator.py:254`), so the DEBUG
     lines for logprobs and structured generation do not appear in the worker log. Do not
     change that. The feature evidence comes from Part A, which uses the same backend and
     pins. Here, record only that each task group produced records with no failed
     instances.

4. **Auth reuse.** Restart `b2-worker`. **Pass:** no device-flow prompt appears.
5. **Cancellation.**
   - Run the worker under the harness in the foreground (`b5-worker`). While an
     evaluation is running, press **Ctrl-C in that terminal** (rule 4).
   - **Pass:**
     - `stop_reason` is `"operator signal 2"`, and `leftover_owned_pids` is empty;
     - `kill -0 $UNRELATED` still succeeds;
     - `probe.py $S` shows `credential_present: true` and a `lease_id`. Save it as
       `$RUN/b5-before.json`.
   - Restart before the lease expires (`b5-resume`). **Pass:** the log shows the same
     lease being processed, and either `probe.py` shows the same `lease_id` while it is
     active, or `last_submission_id` later equals that `lease_id`.

6. **Upload retry.**
   - While a lease is submitting, poll `probe.py $S` once a second, appending each output
     line to `$RUN/b6-poll.jsonl`.
   - As soon as at least one record has `acknowledged: true` and
     `finalised_submission_id` is null, stop the worker hard.
     - Use `kill -9` on the harness PID **and** on its child group. The harness PID is
       printed by `$!`, or found with `pgrep -f "h.py b6-worker"`. The child group's ID is
       the `pgid` in `b6-worker.start`.
     - A hard kill is the point of this test, so the harness cannot write results for
       this one run.
   - Save the last poll line as `$RUN/b6-before.json`: lease ID, digests and acknowledged
     flags.
   - Restart under the harness (`b6-resume`), and keep polling into the same file.
   - **Pass:**
     - Every snapshot taken while that lease is still active after the restart shows the
       same `lease_id` and unchanged digests. The records acknowledged in
       `b6-before.json` are still acknowledged.
     - Completion: `last_submission_id` becomes the `lease_id` from `b6-before.json`, and
       the worker log contains `Volunteer submission completed: <that lease_id>`.
   - **Unproven, not failed:**
     - If no snapshot catches the resumed lease before finalisation deletes
       `active-lease.json`, report the digest comparison as unproven. Completion can
       still pass.
     - The worker does not log individual record sends. So "acknowledged records were
       not sent again" rests on the code path (`runtime.py:897-904` skips acknowledged
       records) and the existing unit tests. Report the live "no duplicate request" check
       as **unproven**.

7. **Oversized model and unsupported model.** These need queue fixtures from the operator:
   a model above this Mac's budget, and a Metal-unsupported architecture such as
   `state-spaces/mamba-130m-hf`.
   - **Oversized:** the worker must never receive a lease for it. This is enforced today
     by the existing fit check.
   - **Unsupported:** record what happens. Today's broker has neither the 4a filter nor
     4b declines, so expect the existing 3 failed attempts followed by release. The
     worker must keep running (change 5). Mark the "not re-leased" part **pending
     deploy**.
   - If the operator cannot arrange fixtures, mark the rows **unproven**.
8. **Mid-size headroom.** Run
   `python3 $RUN/h.py b8-7b $EE --model Qwen/Qwen2.5-7B-Instruct --dataset sst5 --num-iterations 1 --gpu-memory-utilization $U`.
   - **Pass:** exit 0, `stop_reason` null, peak pressure ≤ 2, and swap delta ≤ 256 MiB.
9. **Docs.** Follow the new "Direct execution (no Docker)" section of `VOLUNTEER_WORKER.md`
   literally, using this clone and `make install`. Record any step that was wrong or
   missing.
10. **Pending deploy.** Do not report these as passed: the `unattested` digest in the
    manifest (3), claim-time filtering (4a), and the no-re-lease decline (4b).

## Report

1. **Write the comment.** Put it in `$RUN/comment.md`, under about 50 lines, in the style
   of the Step 0 comment:
   - the branch commit, the pins, and `u` with its inputs;
   - a row per numbered item: **pass**, **fail**, **unproven** or **pending deploy**,
     with the key evidence line;
   - any gaps.
2. **Get approval.** Show the comment to the operator. Post it only after approval:
   `gh issue comment 2310 --repo EuroEval/EuroEval --body-file $RUN/comment.md`.
3. **Archive.** Copy `$RUN` (logs, `*.result.json`, `*.samples.json`, the audits,
   `u.json` and the comment) for transfer back. Exclude `state.json` from `$S`.
