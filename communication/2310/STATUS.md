# Issue 2310 status

Last updated by the Mac on 2026-11-25. This records the last tested implementation commit, not the current head of the feature branch.

Issue: <https://github.com/EuroEval/EuroEval/issues/2310>
Implementation branch: `feat/2310-apple-gpu-worker` in `TheAstroByte/EuroEval`.
Coordination branch: `coord/2310` in the same fork.

## Current handoff

**Gate A failed at A1 on `cc594abe4203db850d9edd9216596a1834d2a87e`.**

The Darwin vLLM/vllm-metal v0.30.0 pair installed on retry. Qwen3-0.6B then loaded its weights on Metal but failed at KV-cache startup because the Git-installed package lacks `_paged_ops.cpython-312-darwin.so`. The exception is raised at upstream `vllm_metal/metal/__init__.py:232`.

A1 exited 1 with normal pressure, zero swap growth, and no owned PIDs left. The persisted inference fraction for that attempt was `u=0.4796`. A2, A3, and A4 were not run because the brief requires stopping after A1 fails. Gate A has not passed. Part B has not started.

The error names a release wheel or `VLLM_METAL_BUILD_FROM_SOURCE=1` as possible installation paths. Neither workaround has been tested on the Mac. The implementation machine owns the next change; the Mac made no implementation or lock changes.

## Next action

The implementation machine can address the missing native artifact and add a dated note under `implementation-notes/` with the pushed SHA and requested Gate A rerun. The Mac waits for the operator's next run instruction. The next run will compute a fresh `u` once and retain a separate result directory.

Use the [Mac run brief](briefs/2026-11-25-mac-run-brief.md) together with the [operator's updates](briefs/2026-11-25-mac-run-updates.md). The update selects v0.30.0, requires the supplied pins paragraph in the report, and records the independent footprint-sampling adjustment.

## Evidence and publication

| Run | Tested commit | Outcome | Report and evidence | Issue publication |
|---|---|---|---|---|
| Step 0 | `6b9d201edecdd7e2d744f7f04ba42ad1e714916d` | Memory-control and inference-feature gaps; canary and cleanup evidence collected | [Findings](mac-results/step0-6b9d201e/findings.md), [handoff](mac-results/step0-6b9d201e/handoff.md), [bundle](mac-results/step0-6b9d201e/evidence.tar.gz) | [Posted with approval](https://github.com/EuroEval/EuroEval/issues/2310#issuecomment-7157791009) |
| Gate A | `cc594abe4203db850d9edd9216596a1834d2a87e` | A1 failed; A2-A4 unproven | [Draft comment](mac-results/gate-a-cc594abe/issue-comment-draft.md), [handoff](mac-results/gate-a-cc594abe/handoff.md), [result](mac-results/gate-a-cc594abe/a1-memory.result.json), [bundle](mac-results/gate-a-cc594abe/evidence.tar.gz) | Draft shared here; not posted to the issue |

The Step 0 controls and scripts are historical. Further tests follow the current brief. Each evidence bundle has a neighbouring SHA-256 file. Archived handoff files describe the state when the archive was made; this status file records current publication and next steps.

## Ownership of updates

- Implementation machine adds commit notes and new run requests under `implementation-notes/` and `briefs/`.
- Mac adds results under `mac-results/`, with tested SHA, exact command, gate status, and evidence paths.
- Each machine pulls before updating this shared status and preserves the other machine's notes.

Keep the coordination branch separate from the feature branch and the upstream pull request. No coordination PR is planned.
