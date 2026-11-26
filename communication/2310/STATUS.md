# Issue 2310 status

Last updated by the Mac on 2026-11-25. This records the last tested implementation commit, not the current head of the feature branch.

Issue: <https://github.com/EuroEval/EuroEval/issues/2310>
Implementation branch: `feat/2310-apple-gpu-worker` in `TheAstroByte/EuroEval`.
Coordination branch: `coord/2310` in the same fork.

## Current handoff

**Gate A passes at `72bd08c5cbebbb804f985ee192ffc8bc9b9579a8` under the amended A1 criterion, with a known non-fatal upstream shutdown diagnostic. Part B ran at `3b88d131128d49a4a141d15268acd88280a6b920`: B1/B4/B8 pass and B9 passes with documentation gaps; B2 is blocked by queue contents (all 15 sampled lease identities were `thinkingmachines/Inkling-2-Mini`; the full log records 51 incompatible-model safety skips; the worker kept running, change 5 fresh path); B3/B5/B6/B7 unproven; broker rows 3 and 4b pending deploy.**

The implementation machine accepted A1 on arithmetic; see [the A1 review and A2–A4 request](implementation-notes/2026-11-25-72bd08c5-a1-review-and-a2-a4-request.md). The earlier bundle `mac-results/gate-a-72bd08c5/` (wheel fix, A1 at `u=0.5498`, `metal_limit` unproven, teardown diagnostic first observed) stays unchanged as historical evidence. The Mac did not repeat A1.

The Mac then ran A2–A4 at the exact same commit with a fresh `u=0.5983` (available 42,701,389,824 B, MLX cap 55,662,788,608 B, usable 41,627,648,000 B; cap × u = 33.303 GB), writing to `mac-results/gate-a-72bd08c5-a2a4/`:

- Every new run satisfies the amended A1 criterion: logged utilization 0.60, KV budget 31.27 GB for Qwen (remainder 2.03 GB) and 31.76 GB for SmolLM2 (remainder 1.54 GB) against cap × u.
- **A2–A4 all pass:** SST-5 and HellaSwag (10 iterations per shot mode, logprobs and structured generation logged, zero fallbacks), CoNLL strict schema audits (zero-shot 252, few-shot 1,608 unique outputs; zero invalid JSON or schema violations), the two-model switch, SQuAD, CNN/DailyMail (zero failed instances), the contamination canary (`status=collected, count=256`), and the Ctrl-C test (`operator signal 2`, no owned PIDs). All eight non-interrupted commands exited 0. The intentional Ctrl-C run exited 1. All nine runs stayed at peak pressure 1 with 0 MiB swap growth and no leftover owned PIDs.
- **The teardown segfault is a known, non-fatal upstream shutdown diagnostic for this test.** In the A4 switch, one `Segfault encountered` (vLLM v0.30.0 `torch.accelerator.empty_host_cache()` in `cleanup_dist_env_and_memory()`) fired before SmolLM2 was announced; the first engine then exited and the owned-group physical footprint fell from 35,454.904 to 1,156.394 MiB before the second model loaded; SmolLM2 loaded and scored both shot modes in the same CLI parent (four benchmarks completed). No patch or workaround was made. Worker lease acceptance after this diagnostic remains unproven: Part B ran, but its leases failed before evaluation.

## Next action

**Implementation machine, 2026-11-26 (later):** the feature branch is at `506502fc` after council round 2. A Mac run is requested on both the 24 GB and the 64 GB Mac; see [the run request](implementation-notes/2026-11-26-506502fc-mac-run-request.md). It covers the new GPU probe, macOS worker tests and direct runs. No live worker until Dan deploys the broker.

**Implementation machine, 2026-11-26:** draft PR [EuroEval/EuroEval#2322](https://github.com/EuroEval/EuroEval/pull/2322) is open from `feat/2310-apple-gpu-worker` at `58f178e3`. The summary is posted on [#2310](https://github.com/EuroEval/EuroEval/issues/2310#issuecomment-7187464157). Since Part B:

- **`de03da42`:** consecutive safety skips now back off 30 s → 300 s, and the count resets after a lease gets through. Part B had shown a constant ~39 s cadence, because each successful claim reset the shared backoff.
- **`80fd3364`:** a test for that reset on the resumed path.
- **`f8e942d7`, `58f178e3`:** the B9 docs gaps, plus the macOS 15+ and Node.js prerequisites.

**Waiting on Dan:** review, and deploying the broker together with the merge. The decline change (4b) is what stops repeat offers of unrunnable models such as Inkling-2-Mini (#2305).

**Mac:** nothing to run until the broker is deployed. Then rerun Part B's remaining live checks:

- two finalised leases and task-group coverage;
- interrupt and resume;
- upload retry;
- oversized and unsupported models;
- the shutdown diagnostic across leases;
- the provenance and decline rows.

Do not rerun Part B before the deploy. Every claim and release edits the model's public request issue.

Use the [Mac run brief](briefs/2026-11-25-mac-run-brief.md) together with the [operator's updates](briefs/2026-11-25-mac-run-updates.md). The update selects v0.30.0, requires the supplied pins paragraph in the report, and records the independent footprint-sampling adjustment.

## Evidence and publication

| Run | Tested commit | Outcome | Report and evidence | Issue publication |
|---|---|---|---|---|
| Step 0 | `6b9d201edecdd7e2d744f7f04ba42ad1e714916d` | Memory-control and inference-feature gaps; canary and cleanup evidence collected | [Findings](mac-results/step0-6b9d201e/findings.md), [handoff](mac-results/step0-6b9d201e/handoff.md), [bundle](mac-results/step0-6b9d201e/evidence.tar.gz) | [Posted with approval](https://github.com/EuroEval/EuroEval/issues/2310#issuecomment-7157791009) |
| Gate A | `cc594abe4203db850d9edd9216596a1834d2a87e` | A1 failed; A2-A4 unproven | [Draft comment](mac-results/gate-a-cc594abe/issue-comment-draft.md), [handoff](mac-results/gate-a-cc594abe/handoff.md), [result](mac-results/gate-a-cc594abe/a1-memory.result.json), [bundle](mac-results/gate-a-cc594abe/evidence.tar.gz) | Draft shared here; not posted to the issue |
| Gate A rerun | `72bd08c5cbebbb804f985ee192ffc8bc9b9579a8` | Wheel fixed; A1 cap evidence unproven and native teardown diagnostic; A2-A4 unproven | [Draft comment](mac-results/gate-a-72bd08c5/issue-comment-draft.md), [handoff](mac-results/gate-a-72bd08c5/handoff.md), [result](mac-results/gate-a-72bd08c5/a1-memory.result.json), [bundle](mac-results/gate-a-72bd08c5/evidence.tar.gz) | Draft shared here; not posted to the issue |
| Gate A A2–A4 | `72bd08c5cbebbb804f985ee192ffc8bc9b9579a8` | PASS under the amended A1 criterion; A2-A4, canary and Ctrl-C pass; known non-fatal upstream teardown diagnostic (worker acceptance unproven); Part B not run | [Draft comment](mac-results/gate-a-72bd08c5-a2a4/issue-comment-draft.md), [handoff](mac-results/gate-a-72bd08c5-a2a4/handoff.md), [summary](mac-results/gate-a-72bd08c5-a2a4/summary.json), [interrupt audit](mac-results/gate-a-72bd08c5-a2a4/a4-interrupt.audit.json), [bundle](mac-results/gate-a-72bd08c5-a2a4/evidence.tar.gz) | Draft only; not posted to the issue |
| Part B | `3b88d131128d49a4a141d15268acd88280a6b920` | B1/B4/B8 pass, B9 pass with doc gaps; B2 blocked/unproven (queue compatibility blocked evaluation; worker kept running after 51 incompatible-model safety skips; all 15 sampled identities were Inkling); B3/B5/B6/B7 unproven; rows 3/4b pending deploy | [Draft comment](mac-results/part-b-3b88d131/issue-comment-draft.md), [handoff](mac-results/part-b-3b88d131/handoff.md), [summary](mac-results/part-b-3b88d131/summary.json), [bundle](mac-results/part-b-3b88d131/evidence.tar.gz) | Draft only; not posted to the issue |

The Step 0 controls and scripts are historical. Further tests follow the current brief. Each evidence bundle has a neighbouring SHA-256 file. Archived handoff files describe the state when the archive was made; this status file records current publication and next steps.

## Ownership of updates

- Implementation machine adds commit notes and new run requests under `implementation-notes/` and `briefs/`.
- Mac adds results under `mac-results/`, with tested SHA, exact command, gate status, and evidence paths.
- Each machine pulls before updating this shared status and preserves the other machine's notes.

Keep the coordination branch separate from the feature branch and the upstream pull request. No coordination PR is planned.
