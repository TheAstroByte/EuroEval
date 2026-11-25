# Issue 2310 status

Last updated by the Mac on 2026-11-25. This records the last tested implementation commit, not the current head of the feature branch.

Issue: <https://github.com/EuroEval/EuroEval/issues/2310>
Implementation branch: `feat/2310-apple-gpu-worker` in `TheAstroByte/EuroEval`.
Coordination branch: `coord/2310` in the same fork.

## Current handoff

**Gate A is not passed at A1 on `72bd08c5cbebbb804f985ee192ffc8bc9b9579a8`.**

The release wheel fixes the missing native extension from `cc594abe`. Fresh `make install` completed, the extension check printed `True`, the wheel checksum matched the implementation note, and the installed `.so` matched the wheel byte for byte. The vLLM/vllm-metal pair remains v0.30.0/v0.30.0 on Darwin.

A1 loaded native Metal kernels and completed both SST-5 shot modes at the fresh persisted `u=0.5498`. Its outer exit was 0, pressure stayed 1, swap growth was 0 MiB, and no owned PIDs remained. Two observations prevent a clean gate result:

- The required `metal_limit` log has zero matches. The default upstream cache-layout path logs a 28.57 GB KV budget instead. Source inspection shows an MLX cap lookup, but this is not the required runtime cap-log evidence.
- After `Metal worker shutdown complete`, the log prints `Segfault encountered`, with `TVMFFIEnvRegisterCAPI` and `at::accelerator::emptyHostCache()` frames. The outer CLI still reports completion and exits 0. The faulting process and root cause have not been isolated.

A2-A4 were not run after the unmet A1 gate. A5's feature-reproduction branch was not triggered. Part B has not started. The Mac made no implementation or lock changes.

## Next action

**Implementation machine, 2026-11-25:** reviewed the `72bd08c5` A1 result; see [the A1 review and A2–A4 request](implementation-notes/2026-11-25-72bd08c5-a1-review-and-a2-a4-request.md).

- **A1 memory control is accepted on arithmetic.** cap × u = 30.60 GB, minus the logged KV budget of 28.57 GB, leaves 2.03 GB for model and overhead. That matches Step 0, so the denominator is the MLX cap. The brief's `metal_limit` log requirement is replaced by an amended criterion in the note.
- **The teardown segfault is traced to upstream.** vLLM v0.30.0 added `torch.accelerator.empty_host_cache()` to `cleanup_dist_env_and_memory()`, and v0.27.1 does not have it. The main process survived. It may matter because the worker runs every lease in one process. Nothing is patched yet.

**Mac:** when the operator instructs, run A2–A4 at `72bd08c5` with a fresh `u`, in `mac-results/gate-a-72bd08c5-a2a4/`. A4's two-model switch is the test that decides whether the teardown segfault matters. Part B remains excluded.

Use the [Mac run brief](briefs/2026-11-25-mac-run-brief.md) together with the [operator's updates](briefs/2026-11-25-mac-run-updates.md). The update selects v0.30.0, requires the supplied pins paragraph in the report, and records the independent footprint-sampling adjustment.

## Evidence and publication

| Run | Tested commit | Outcome | Report and evidence | Issue publication |
|---|---|---|---|---|
| Step 0 | `6b9d201edecdd7e2d744f7f04ba42ad1e714916d` | Memory-control and inference-feature gaps; canary and cleanup evidence collected | [Findings](mac-results/step0-6b9d201e/findings.md), [handoff](mac-results/step0-6b9d201e/handoff.md), [bundle](mac-results/step0-6b9d201e/evidence.tar.gz) | [Posted with approval](https://github.com/EuroEval/EuroEval/issues/2310#issuecomment-7157791009) |
| Gate A | `cc594abe4203db850d9edd9216596a1834d2a87e` | A1 failed; A2-A4 unproven | [Draft comment](mac-results/gate-a-cc594abe/issue-comment-draft.md), [handoff](mac-results/gate-a-cc594abe/handoff.md), [result](mac-results/gate-a-cc594abe/a1-memory.result.json), [bundle](mac-results/gate-a-cc594abe/evidence.tar.gz) | Draft shared here; not posted to the issue |
| Gate A rerun | `72bd08c5cbebbb804f985ee192ffc8bc9b9579a8` | Wheel fixed; A1 cap evidence unproven and native teardown diagnostic; A2-A4 unproven | [Draft comment](mac-results/gate-a-72bd08c5/issue-comment-draft.md), [handoff](mac-results/gate-a-72bd08c5/handoff.md), [result](mac-results/gate-a-72bd08c5/a1-memory.result.json), [bundle](mac-results/gate-a-72bd08c5/evidence.tar.gz) | Draft shared here; not posted to the issue |

The Step 0 controls and scripts are historical. Further tests follow the current brief. Each evidence bundle has a neighbouring SHA-256 file. Archived handoff files describe the state when the archive was made; this status file records current publication and next steps.

## Ownership of updates

- Implementation machine adds commit notes and new run requests under `implementation-notes/` and `briefs/`.
- Mac adds results under `mac-results/`, with tested SHA, exact command, gate status, and evidence paths.
- Each machine pulls before updating this shared status and preserves the other machine's notes.

Keep the coordination branch separate from the feature branch and the upstream pull request. No coordination PR is planned.
