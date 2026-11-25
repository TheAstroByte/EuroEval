## Gate A findings: stopped at A1

Branch `feat/2310-apple-gpu-worker` @ `cc594abe4203db850d9edd9216596a1834d2a87e`.
Pins: macOS vLLM **v0.30.0** / vllm-metal **v0.30.0**; installed vLLM 0.30.0+cpu, vllm-metal 0.30.0, MLX 0.32.1, Transformers 5.14.1, torch 2.13.0.

**Why v0.30.0 and not newer.** vllm-metal and vLLM are released in matching pairs.
v0.30.0 is the first vllm-metal release that sizes its KV cache from vLLM's
`gpu_memory_utilization` (vllm-metal#756) rather than `VLLM_METAL_MEMORY_FRACTION`,
and it also includes vllm-metal#587 (structured-output bitmask rows) and #667
(requested logprobs). Newer pairs (v0.31+, checked up to v0.34.0) require
`transformers>=5.16.1`. That conflicts with EuroEval's project-wide override
`transformers>=5.14.0,<5.15.0`, which exists because vLLM 0.27.1 on Linux breaks on
Transformers 5.15. Moving beyond v0.30.0 on macOS therefore needs that override
lifted, which means bumping Linux vLLM too. That is out of scope for #2310. The
change is Darwin-only: Linux keeps vllm 0.27.1, Transformers 5.14.1 and torch 2.13.0.

Machine: Apple M3 Max, 64 GiB, macOS 27.0.1, arm64 Python 3.12.13.
Persisted `u=0.4796`: available 34,446,508,032 B; cap 55,662,788,608 B;
usable `min(cap, available - 1 GiB)` = 33,372,766,208 B; `u=round(0.8*usable/cap,4)`.
No `VLLM_METAL_MEMORY_FRACTION` override was used. No live worker or broker work ran.

| Item | Status | Evidence |
|---|---|---|
| Setup | pass on retry | `make install` completed unchanged in 126.21 s after an initial uv local Git-cache pack-copy error. No lock repair. |
| A1 memory control | **fail** | Engine startup exits 1 before scoring. `stop_reason=null`, pressure 1, swap growth 0 MiB, `leftover_owned_pids=[]`. |
| A2 logprobs and labels | unproven | Not run: the brief requires stopping Part A when A1 fails. |
| A3 per-mode CoNLL audits | unproven | Not run after A1 failure. |
| A4 generation, canary, switching, Ctrl-C | unproven | Not run after A1 failure. Harness-only cancellation smoke passed; it does not establish A4. |
| A5 reduced feature reproduction | unproven | Conditional branch not entered: A1 must pass before reproducing A2/A3 failures. |

The model weights loaded on MLX GPU. The plugin logged `Paged attention: using --gpu-memory-utilization=0.48` and a 24.66 GB KV budget. The utilisation display rounds the requested 0.4796; the required `metal_limit` log evidence was not established before startup failed.

Blocker: upstream `vllm_metal/metal/__init__.py:232` raises `RuntimeError: Prebuilt native extension not found` for `vllm_metal/metal/_paged_ops.cpython-312-darwin.so` in the installed package.
The exception explicitly recommends a release wheel or `VLLM_METAL_BUILD_FROM_SOURCE=1` with Command Line Tools. The pinned Git-source install did not provide the prebuilt extension; its `setup.py` packages prebuilt artifacts without invoking a compiler.
EuroEval wraps this as generic `InvalidModel` at `src/euroeval/benchmark_modules/vllm.py:2271`. Full traceback, results and samples are archived.

Stopped per A1's failure rule. Neither suggested workaround was tried. No implementation changes, lock changes, commits, pushes, or upstream issue were made. Gate A has not passed.
