# EuroEval 2310 Gate A at cc594abe

Gate A failed at A1. The fresh contributor install completed on retry, but the model could not initialise because the Git-installed vllm-metal package lacks its required prebuilt native extension. Part A stopped at that point, as the brief requires.

Read `comment.md` for the approval-ready issue comment. It contains the operator's required v0.30.0 rationale verbatim immediately after the pins line. No comment has been posted for this run.

## Tested setup

- Fork: `https://github.com/TheAstroByte/EuroEval`.
- Branch: `feat/2310-apple-gpu-worker`.
- Commit: `cc594abe4203db850d9edd9216596a1834d2a87e`.
- Fresh clone: `/Users/daniel/Developer/EuroEval-2310`.
- Darwin pair: vLLM 0.30.0+cpu and vllm-metal 0.30.0.
- Other installed versions: MLX 0.32.1, mlx-lm 0.32.0, Transformers 5.14.1, torch 2.13.0.
- Machine: Apple M3 Max, 64 GiB, macOS 27.0.1, native arm64 Python 3.12.13.

`install.log` records the initial uv Git-cache pack-copy failure. `install-retry.log` records the unchanged successful retry. The lockfile resolved without repair. `install-package-lock.diff` records the npm-generated change that was restored to the tested commit. Both source checkouts remain without tracked changes.

## A1 evidence

The model was `Qwen/Qwen3-0.6B#no-thinking`. `a1-memory.start` records the exact command, process group, harness PID and memory baseline. `u.json` records the once-computed inference fraction 0.4796 and its inputs. No legacy Metal memory-fraction setting was passed to the evaluation.

The checkpoint loaded on `Device(gpu, 0)`. The plugin logged the CLI memory utilisation as 0.48, rounded from 0.4796, and a 24.66 GB KV budget. It then failed during KV-cache initialisation, before producing scores. The exact exception is in `startup-exception.txt` and the full traceback in `a1-memory.log`.

The upstream exception occurs at `vllm_metal/metal/__init__.py:232`. That loader defaults to a prebuilt `_paged_ops.cpython-312-darwin.so`. When the artifact is absent, it requires an explicit source-build opt-in instead of compiling silently. The pinned `setup.py` describes itself as packaging prebuilt artifacts without invoking a compiler.

The error suggests a release wheel or `VLLM_METAL_BUILD_FROM_SOURCE=1` with Command Line Tools. Neither was tried. This is a packaging/startup blocker to return to the implementation machine, not evidence of an inference-feature failure or a verified workaround. The strict A1 runtime `metal_limit` log requirement was also not established before failure.

EuroEval wraps the upstream startup exception as generic `InvalidModel` at `src/euroeval/benchmark_modules/vllm.py:2271`. No source or dependency patch was made on the Mac.

`a1-memory.result.json` records exit 1, no safety stop, peak pressure 1, zero swap growth, and no owned PIDs left. `a1-memory.samples.json` contains 43 memory samples. The largest interval between sample timestamps was about 2.034 seconds. The footprint worker was independent and did not delay the guard loop.

## Harness adjustment

The brief's original synchronous footprint loop could block safety checks for six calls of up to three seconds each. The new `/tmp` harness keeps that work in one independent thread. Each footprint call is still capped at three seconds and only six owned PIDs are inspected. Every memory sample is checked for the safety conditions before footprint work is scheduled or consumed.

The guard refuses baseline pressure at least 2 and stops at the first sampled pressure 4 or swap growth above 1 GiB. The pass threshold remains swap growth no greater than 256 MiB. `footprint` uses byte output, with raw snapshots preserved. Their start and end times make the measurement span explicit.

INT, TERM and HUP to the harness record the operator signal and invoke owned-group cleanup with INT, TERM and KILL escalation. The root is reaped during cleanup. A separate root-plus-child smoke test records `operator signal 2` and no surviving owned PIDs in `harness-smoke.result.json`. That verifies harness handling only; it is not the A4 model-interrupt acceptance result.

No Step 0 scripts were reused. The current harness and schema auditor were created from the new brief. `MAX_RUN_SECONDS` defaults to one hour per command. The planned Gate A evaluation budget was three hours; this attempt stopped after its first 84-second model run.

## Unproven rows and next run

A2, A3 and A4 were not run after A1 failed. A5's reduced `LLM.generate` reproduction was not triggered because it requires A1 to pass and A2 or A3 to fail. No upstream issue was filed or drafted for that conditional feature-failure path.

Part B remains unauthorised and unrun. No live worker, authentication, claim, upload, or broker fixture was exercised.

After the implementation machine addresses the native-artifact installation path, a newly authorised Gate A attempt should record the new commit and use a fresh results directory. Existing result files are preserved and the harness refuses to overwrite them.

## Archive contents

- `request.md` is the supplied run brief.
- `required-pin-rationale.md` preserves the operator's update verbatim.
- `branch-change.txt`, `commit.txt`, `pin-config.txt`, and `*-origin.json` record provenance.
- `pinned-cache-policy.py`, `pinned-metal-init.py`, and `pinned-metal-setup.py` are read-only copies of the tested upstream code.
- `a1-memory.*` contains the complete model attempt, guard samples, footprint captures and result.
- `h.py`, `audit.py`, and `harness-smoke*` preserve the instrumentation and smoke evidence.
- `summary.json` records the outcome and the unproven rows.
- `manifest.json` provides file hashes.

No `.env`, worker credentials, model weights or virtual environment are included. The archive is local and ready to transfer; publication still needs the operator's approval.
