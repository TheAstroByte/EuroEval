## Gate A rerun: wheel startup fixed, A1 still not fully proven

Branch `feat/2310-apple-gpu-worker` @ `72bd08c5cbebbb804f985ee192ffc8bc9b9579a8`.
Pins: Darwin vLLM v0.30.0 / vllm-metal v0.30.0; installed vLLM 0.30.0+cpu, MLX 0.32.1, Transformers 5.14.1, torch 2.13.0.

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

Install source is now the v0.30.0 release wheel, to provide the native extension missing from the previous Git install. `make install` completed on its first attempt in 11.531 s. The requested extension check printed `True`; metadata confirms the wheel URL. Its SHA-256 matches the implementation note, and the installed `.so` matches the downloaded wheel byte for byte.
Machine: Apple M3 Max, 64 GiB, macOS 27.0.1, arm64 Python 3.12.13.
Fresh persisted `u=0.5498`: available 39,326,466,048 B, cap 55,662,788,608 B, usable 38,252,724,224 B; `u=round(0.8*usable/cap,4)`.

| Item | Status | Evidence |
|---|---|---|
| Setup and native extension | pass | Release wheel verified; no source-build flag, lock repair or implementation change. |
| A1 memory control | unproven | Both shot modes scored; exit 0, `stop_reason=null`, pressure 1, swap growth 0 MiB, no owned PIDs left. Required `metal_limit` log has zero matches. Native shutdown segfault diagnostic also observed. |
| A2 logprobs and labels | unproven | Not run because A1 did not fully meet its gate. Pilot A1 logged logprobs/structured labels and no fallback; it is not the required ten-iteration A2 evidence. |
| A3 per-mode CoNLL audits | unproven | Not run after unmet A1 gate. |
| A4 regressions, canary, switching, Ctrl-C | unproven | Not run after unmet A1 gate. |
| A5 reduced feature reproduction | unproven | Not triggered: requires A1 to pass and A2/A3 to fail. |

A1 logged native Metal kernels and `using --gpu-memory-utilization=0.55`, rounded from 0.5498. It reported a 28.57 GB KV budget. The installed default upstream cache-layout path logs the budget without `metal_limit` (`vllm_metal/v1/cache_policy.py:954-967`); its cap lookup reads MLX's recommended working-set limit at lines 1049-1059. This source observation does not replace the brief's required runtime cap-log evidence.

After `Metal worker shutdown complete`, the log prints `!!!!!!! Segfault encountered !!!!!!!`, including `TVMFFIEnvRegisterCAPI` and `at::accelerator::emptyHostCache()` native frames. The outer CLI nevertheless prints `Completed 2 benchmarks` and exits 0. The faulting process and native cause are not isolated. A matching host-cache call exists at vLLM `distributed/parallel_state.py:2467`, which is a source lead rather than proven localisation.

Gate A remains not passed. Reconcile the cap-evidence check with the actual cache-layout logging and investigate the native teardown diagnostic before proceeding. Full logs, guard results, samples, wheel verification and source excerpts are archived. No A2-A4 run, backend patch, environment workaround, live worker, implementation commit or issue post was made on the Mac.
