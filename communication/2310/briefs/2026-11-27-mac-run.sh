#!/bin/bash
# Mac run for EuroEval #2310 / PR #2322 at the commit below.
#
# Runs the same checks on any Apple Silicon Mac (24 GB and 64 GB):
#   1. a checkout of the exact commit and `make install`;
#   2. the worker's Apple GPU probe, its timing, and two CPU-steering refusals;
#   3. the worker test files on macOS;
#   4. direct `euroeval` runs under the memory-guard harness: a 0.6B and a 3B
#      generative model at the worker's `u`, and one small encoder model.
#
# It never starts `euroeval-worker` and never contacts the volunteer broker.
# Results go to ../mac-results/run-<sha8>-<ram>gb/ next to this script.
#
# Usage, from any directory:  bash /path/to/2026-11-27-mac-run.sh
# The only prompts are from `make install` writing `.env`: press Enter at each.

set -u
SHA="506502fcc4de6c4f4e842c1ebc2d7ba178ea0157"
SHORT="${SHA:0:8}"
FORK_URL="https://github.com/TheAstroByte/EuroEval.git"
BRANCH="feat/2310-apple-gpu-worker"
HERE="$(cd "$(dirname "$0")" && pwd)"

say() { printf '\n== %s ==\n' "$*"; }
fail() { printf '\nSTOPPED: %s\n' "$*"; exit 1; }

# --- 0. Preflight -----------------------------------------------------------------
say "0. Preflight"
[ "$(uname -s)" = "Darwin" ] && [ "$(uname -m)" = "arm64" ] || fail "this is not an Apple Silicon Mac"
RAM_BYTES="$(sysctl -n hw.memsize)"
RAM_GB=$(( RAM_BYTES / 1024 / 1024 / 1024 ))
OUT="$HERE/../mac-results/run-$SHORT-${RAM_GB}gb"
[ -e "$OUT" ] && fail "$OUT already exists; move it away to keep the earlier results"
mkdir -p "$OUT" || fail "cannot create $OUT"
OUT="$(cd "$OUT" && pwd)" || fail "cannot enter $OUT"
case "$OUT" in
  */mac-results/run-"$SHORT"-*gb) [ -d "$OUT" ] || fail "results folder $OUT is missing" ;;
  *) fail "unexpected results folder '$OUT'" ;;
esac
RUN="$OUT"; export RUN
FAILURES=""
note_failure() { FAILURES="$FAILURES $1"; }
SRC="$HOME/Developer/worktrees/EuroEval/2310-mac-run-$SHORT"
{
  echo "date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "chip: $(sysctl -n machdep.cpu.brand_string)"
  echo "ram_bytes: $RAM_BYTES"
  echo "macos: $(sw_vers -productVersion) ($(sw_vers -buildVersion))"
  echo "commit: $SHA"
  echo "checkout: $SRC"
} | tee "$OUT/machine.txt"
PRESSURE="$(sysctl -n kern.memorystatus_vm_pressure_level)"
echo "memory pressure level: $PRESSURE (1 = normal)"
[ "$PRESSURE" -lt 2 ] || fail "memory pressure is not normal; quit heavy apps (and the Docker sandbox) and rerun"
command -v git >/dev/null || fail "git is missing; run: xcode-select --install"
xcode-select -p >/dev/null 2>&1 || fail "Xcode Command Line Tools are missing; run: xcode-select --install"
command -v npm >/dev/null || fail "npm is missing; install Node.js from https://nodejs.org/ and rerun"

# --- 1. Checkout ------------------------------------------------------------------
say "1. Checkout at $SHORT"
if [ -e "$SRC" ]; then
  [ "$(git -C "$SRC" rev-parse HEAD 2>/dev/null)" = "$SHA" ] || fail "$SRC exists at another commit; remove it and rerun"
  echo "reusing $SRC"
elif git -C "$HOME/Developer/EuroEval" rev-parse --git-dir >/dev/null 2>&1; then
  git -C "$HOME/Developer/EuroEval" fetch --quiet "$FORK_URL" "$BRANCH" || fail "git fetch failed"
  git -C "$HOME/Developer/EuroEval" worktree add --detach "$SRC" "$SHA" || fail "git worktree add failed"
else
  mkdir -p "$(dirname "$SRC")"
  git clone --quiet --branch "$BRANCH" "$FORK_URL" "$SRC" || fail "git clone failed"
  git -C "$SRC" checkout --quiet --detach "$SHA" || fail "commit $SHA is not on $BRANCH"
fi
cd "$SRC" || fail "cannot enter $SRC"
[ "$(git rev-parse HEAD)" = "$SHA" ] || fail "checkout is not at $SHA"
git log --oneline -1 | tee "$OUT/commit.txt"

# --- 2. make install --------------------------------------------------------------
say "2. make install (press Enter at each .env prompt)"
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
START=$(date +%s)
make install
INSTALL_EXIT=$?
echo "make install exit $INSTALL_EXIT after $(( $(date +%s) - START )) s" | tee "$OUT/install.txt"
[ "$INSTALL_EXIT" -eq 0 ] || fail "make install failed; see the output above"
git status --porcelain --untracked-files=no | tee -a "$OUT/install.txt"

{
  uv run python -c "import importlib.metadata as m; [print(p, m.version(p)) for p in ('euroeval','vllm','vllm-metal','mlx','mlx-lm','torch','transformers','huggingface-hub')]"
  uv run python -c "import sys; print('python', sys.version.split()[0])"
  echo "native extension present:"
  uv run python -c "import vllm_metal, pathlib; print((pathlib.Path(vllm_metal.__file__).parent / 'metal' / '_paged_ops.cpython-312-darwin.so').exists())"
  echo "vllm-metal source:"
  cat .venv/lib/python3.12/site-packages/vllm_metal-0.30.0.dist-info/direct_url.json; echo
} 2>&1 | tee "$OUT/versions.txt"

# --- 3. Apple GPU probe -----------------------------------------------------------
say "3. Apple GPU probe"
cat > "$OUT/probe_hw.py" <<'PY'
"""Time the worker's hardware discovery and check it against independent readings."""
import json, re, subprocess, sys, time
from euroeval_worker.hardware import NoGpuError, discover_hardware

def available():
    vm = subprocess.check_output(["vm_stat"], text=True)
    page = int(re.search(r"page size of (\d+) bytes", vm)[1])
    return sum(int(re.search(rf"Pages {k}:\s+(\d+)", vm)[1]) for k in ("free", "inactive")) * page

cap = int(subprocess.check_output([sys.executable, "-c",
    "import mlx.core as mx; print(mx.device_info()['max_recommended_working_set_size'])"], text=True))
memsize = int(subprocess.check_output(["sysctl", "-n", "hw.memsize"], text=True))
seconds, report, avail = [], None, None
try:
    for _ in range(3):
        avail = available()
        start = time.monotonic()
        report = discover_hardware()
        seconds.append(round(time.monotonic() - start, 2))
except NoGpuError as error:
    print(json.dumps({"pass": False, "error": f"NoGpuError: {error}", "seconds": seconds}))
    sys.exit(1)
gpu = report.gpus[0]
expected_free = min(cap, max(0, avail - 2**30))
checks = {
    "one_gpu_metal_0": len(report.gpus) == 1 and gpu.uuid == "metal-0",
    "total_equals_mlx_cap": gpu.total_memory_bytes == cap,
    "free_within_2pct": abs(gpu.free_memory_bytes - expected_free) <= 0.02 * cap,
    "ram_equals_hw_memsize": report.ram_bytes == memsize,
}
print(json.dumps({"pass": all(checks.values()), "checks": checks, "seconds": seconds,
                  "gpu": {"name": gpu.name, "uuid": gpu.uuid, "total": gpu.total_memory_bytes,
                          "free": gpu.free_memory_bytes},
                  "mlx_cap": cap, "available": avail, "expected_free": expected_free,
                  "ram_bytes": report.ram_bytes, "hw_memsize": memsize,
                  "pytorch_version": report.pytorch_version}, indent=2))
sys.exit(0 if all(checks.values()) else 1)
PY
uv run python "$OUT/probe_hw.py" > "$OUT/probe.json" 2>"$OUT/probe.stderr"
PROBE_EXIT=$?
cat "$OUT/probe.json"
if [ "$PROBE_EXIT" -ne 0 ]; then
  cat "$OUT/probe.stderr"
  echo "PROBE FAILED (exit $PROBE_EXIT): the tests still run, but the direct runs are skipped"
  note_failure probe
fi

cat > "$OUT/refusal.py" <<'PY'
"""Report whether hardware discovery refuses under the current environment."""
import json
from euroeval_worker.hardware import NoGpuError, discover_hardware
try:
    discover_hardware()
    print(json.dumps({"refused": False}))
except NoGpuError as error:
    print(json.dumps({"refused": True, "message": str(error)}))
PY
{
  printf 'VLLM_TARGET_DEVICE=cpu: '; VLLM_TARGET_DEVICE=cpu uv run python "$OUT/refusal.py"
  printf 'VLLM_PLUGINS=none: '; VLLM_PLUGINS=none uv run python "$OUT/refusal.py"
} 2>&1 | tee "$OUT/refusals.txt"

# --- 4. Worker tests on macOS -----------------------------------------------------
say "4. Worker tests on macOS"
uv run pytest -q -p no:cacheprovider tests/test_euroeval_worker.py tests/test_worker_health.py \
  tests/test_worker_review3.py tests/test_worker_assignee.py tests/test_worker_launcher.py \
  > "$OUT/tests.log" 2>&1
TESTS_EXIT=$?
grep -E "passed|failed|error" "$OUT/tests.log" | tail -3
echo "pytest exit $TESTS_EXIT" >> "$OUT/tests.log"
[ "$TESTS_EXIT" -eq 0 ] || note_failure tests

# --- 5. Direct euroeval runs under the harness ------------------------------------
say "5. Direct euroeval runs"
cp "$HERE/mac-run-h.py" "$OUT/h.py" || fail "cannot copy the harness"
cat > "$OUT/compute_u.py" <<'PY'
"""Compute the worker's utilisation u = 0.8 x usable / cap from a fresh snapshot."""
import json, re, subprocess, mlx.core as mx
vm = subprocess.check_output(["vm_stat"], text=True)
page = int(re.search(r"page size of (\d+) bytes", vm)[1])
avail = sum(int(re.search(rf"Pages {k}:\s+(\d+)", vm)[1]) for k in ("free", "inactive")) * page
cap = int(mx.device_info()["max_recommended_working_set_size"])
usable = min(cap, max(0, avail - 2**30))
print(json.dumps({"available": avail, "cap": cap, "usable": usable, "u": round(0.8 * usable / cap, 4)}))
PY
HALT=""
[ "$PROBE_EXIT" -eq 0 ] || HALT="the GPU probe failed"
EE="uv run euroeval --evaluate-val-split --force --no-save-results --raise-errors --verbose"
run_case() {  # name, max seconds, then the euroeval arguments
  local name="$1" limit="$2"; shift 2
  say "5. $name"
  if [ -n "$HALT" ]; then
    echo "skipped: $HALT" | tee "$OUT/$name.skipped.txt"; return
  fi
  MAX_RUN_SECONDS="$limit" python3 "$OUT/h.py" "$name" $EE "$@"
  grep -h "Paged attention\|utilization" "$OUT/$name.log" | head -5
  printf 'Segfault encountered lines: '; grep -c "Segfault encountered" "$OUT/$name.log"
  STATE=$(python3 -c "import json; r=json.load(open('$OUT/$name.result.json')); print('stopped' if r['stop_reason'] else ('ok' if r['exit']==0 else 'failed'))" 2>/dev/null || echo missing)
  case "$STATE" in
    ok) ;;
    failed) note_failure "$name" ;;
    *) note_failure "$name"; HALT="$name was stopped by the harness or left no result" ;;
  esac
}
fresh_u() {  # name: writes $OUT/<name>.u.json and sets U and BUDGET_GB
  uv run python "$OUT/compute_u.py" > "$OUT/$1.u.json" || { note_failure "$1-u"; HALT="could not compute u"; return; }
  U=$(python3 -c "import json; print(json.load(open('$OUT/$1.u.json'))['u'])") &&
    BUDGET_GB=$(python3 -c "import json; d=json.load(open('$OUT/$1.u.json')); print(round(d['cap']*d['u']/1e9, 1))") ||
    { note_failure "$1-u"; HALT="could not read $1.u.json"; return; }
  echo "u=$U, vllm-metal budget cap x u = $BUDGET_GB GB"
  python3 -c "import sys; sys.exit(0 if 0.05 < $U <= 0.8 else 1)" ||
    { note_failure "$1-u"; HALT="u=$U is out of range; quit apps and rerun"; }
}
U=0; BUDGET_GB=0
[ -n "$HALT" ] || fresh_u d1-qwen3-0.6b
run_case d1-qwen3-0.6b 3600 --requires-safetensors --model "Qwen/Qwen3-0.6B#no-thinking" \
  --dataset sst5 --num-iterations 1 --gpu-memory-utilization "$U"
[ -n "$HALT" ] || fresh_u d2-qwen2.5-3b
if [ -z "$HALT" ] && ! python3 -c "import sys; sys.exit(0 if $BUDGET_GB >= 9 else 1)"; then
  echo "skipped: budget $BUDGET_GB GB is below 9 GB, too small for a 3B model" | tee "$OUT/d2-qwen2.5-3b.skipped.txt"
else
  run_case d2-qwen2.5-3b 5400 --requires-safetensors --model Qwen/Qwen2.5-3B-Instruct \
    --dataset sst5 --num-iterations 1 --gpu-memory-utilization "$U"
fi
run_case d3-encoder-electra-small 3600 --model jonfd/electra-small-nordic --dataset angry-tweets \
  --num-iterations 1

# --- 6. Summary -------------------------------------------------------------------
say "6. Summary"
python3 - "$OUT" <<'PY' | tee "$OUT/summary.txt"
import json, sys
from pathlib import Path
out = Path(sys.argv[1])
try:
    probe = json.loads((out / "probe.json").read_text())
except (OSError, ValueError):
    probe = {}
print(f"probe: pass={probe.get('pass')} seconds={probe.get('seconds')} error={probe.get('error')}")
print((out / "refusals.txt").read_text().strip())
print(next((l for l in reversed((out / "tests.log").read_text().splitlines()) if "passed" in l or "failed" in l), "tests: no summary line"))
for f in sorted(out.glob("d*.u.json")):
    print(f"{f.name[:-7]} u: {f.read_text().strip()}")
for f in sorted(out.glob("d*.skipped.txt")):
    print(f"{f.name[:-12]}: {f.read_text().strip()}")
for f in sorted(out.glob("d*.result.json")):
    r = json.loads(f.read_text())
    print(f"{f.name[:-12]}: exit={r['exit']} stop={r['stop_reason']} pressure={r['peak_pressure']} "
          f"swap_delta_mib={r['swap_delta_mib']:.0f} min_available_gib={r['min_available_gib']:.1f} "
          f"peak_footprint_mib={r['peak_footprint_mib']:.0f} leftover={r['leftover_owned_pids']}")
PY

# Pack the raw logs, samples and footprint captures; delete them only once the
# archive is verified to hold every one of them.
cd "$OUT" || fail "cannot enter $OUT"
RAW=$(ls -- *.log *.samples.json *.footprints.json *.start *.footprint-*.txt 2>/dev/null)
if [ -n "$RAW" ]; then
  if tar -czf logs.tar.gz $RAW && tar -tzf logs.tar.gz > logs.list &&
     [ "$(sort logs.list)" = "$(printf '%s\n' $RAW | sort)" ]; then
    rm -f -- $RAW logs.list
  else
    echo "could not verify logs.tar.gz; the raw files are kept"
    rm -f logs.tar.gz logs.list
    note_failure archive
  fi
fi
echo "failures:${FAILURES:- none}" | tee -a "$OUT/summary.txt"
say "Done. Results are in $OUT"
echo "The checkout $SRC and the downloaded models can be removed afterwards."
[ -z "$FAILURES" ]
