# B9 — Direct execution (no Docker) doc check at 3b88d131

Followed VOLUNTEER_WORKER.md "Direct execution (no Docker)" literally with the fresh clone:

1. `git clone` of the repo (fork branch feat/2310-apple-gpu-worker checked out at 3b88d131128d49a4a141d15268acd88280a6b920) — OK.
2. `make install` — exit 0. It installs Rust/uv if missing (both present), `uv sync` with Python 3.12, then prompts for 4 optional env vars (GIT_NAME, GIT_EMAIL, EUROEVAL_PYPI_API_TOKEN, SCANDEVAL_PYPI_API_TOKEN); pressing Enter skips each, exactly as the doc says. Note: `make install` also runs `npm install` and installs the Vercel CLI (frontend steps) — works, but takes extra minutes; the doc does not mention this.
3. `uv run euroeval-worker` — entry point present (version 1.0.0); used `--state-dir ~/.euroeval-worker-2310` as the same section documents. First run printed the GitHub device-flow URL + one-time code exactly as the "Sign in and contribute" section describes; after approval the worker authenticated and claimed work. Later run reused the sign-in with zero prompts (B4).
4. Worker runs until SIGINT/Ctrl-C: harness SIGINT to the harness PID produced `Worker stopped`, exit 130, no leftover owned PIDs (b2-worker-r2, b4-worker). Restart resumes unfinished leases — not exercised (no lease survived the safety preflight).
5. State lives in the --state-dir (default ~/.cache/euroeval-worker per the doc); credential stored in state.json, never printed or archived.
6. "Runs without Docker are recorded with image digest unattested" — broker-side change 3 is pending deploy; not observable from the worker side in this run.

Prerequisites check: arm64 Mac (M3 Max), Xcode CLT present (/Library/Developer/CommandLineTools, Apple clang 21.0.0), 64 GiB unified memory. The doc's claim "stops before claiming work if the GPU cannot be used; never falls back to CPU" matches hardware.py (Metal path only on arm64 Darwin; NoGpuError otherwise) — not triggered here.

Doc gaps recorded:
- The Darwin dependency pair (vllm 0.30.0 + vllm-metal 0.30.0 release wheel) is cp312-only; the section does not say that on macOS with Python != 3.12 vllm-metal is skipped and the Metal route is unavailable. `make install` uses 3.12, so this only matters for manual venvs.
- No mention that queued models whose config the pinned Transformers (>=5.14.0,<5.15.0) cannot parse are released `unsafe_model` at the safety preflight and, until broker change 4b deploys, are re-leased repeatedly; the worker keeps running (change 5) but the queue can look stuck. Observed live with thinkingmachines/Inkling-2-Mini (model_type inkling2_loop, unknown to transformers 5.14.1).
- Removal instructions reference revoking the broker credential via the maintainer; fine, but the section could state that deleting the state dir alone does not revoke the server-side grant.
