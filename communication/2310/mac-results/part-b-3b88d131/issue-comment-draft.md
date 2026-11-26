Part B (worker acceptance) at `3b88d131128d49a4a141d15268acd88280a6b920` on M3 Max, 64 GiB, macOS 27.0.1. Fresh clone, `make install` exit 0; vllm-metal extension check `True` (v0.30.0 release wheel). Dedicated state dir `~/.euroeval-worker-2310`.
Pins on Darwin: vLLM 0.30.0+cpu / vllm-metal 0.30.0 release wheel, MLX 0.32.1, Transformers 5.14.1, torch 2.13.0, euroeval 18.4.0.dev, Python 3.12.13.

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

Fresh `u=0.5687`: available 40,639,905,792 B, MLX cap 55,662,788,608 B, usable 39,566,163,968 B. No legacy Metal fraction override; the worker kept its own 0.8 offer factor (no `--gpu-memory-utilization` passed to `euroeval-worker`).

| Item | Result | Evidence |
|---|---|---|
| Setup / install / extension | Pass | `make install` exit 0; `_paged_ops.cpython-312-darwin.so` present (`True`); wheel URL in `direct_url.json` |
| B1 hardware | Pass | one `metal-0`; total=cap 55,662,788,608 B; free 39,635,828,736 vs min(cap, avail−1 GiB) 39,635,599,360 (0.0006%); ram=sysctl hw.memsize; post-run `pgrep nvidia-smi` snapshot none, not continuous launch tracing |
| B2 auth + two leases | Blocked/unproven | The complete worker log records 51 incompatible-model safety skips. All 15 sampled lease identities were thinkingmachines/Inkling-2-Mini (lv); the remaining skips have no model identity recorded. The sampled model has model_type inkling2_loop, unknown to Transformers 5.14.1. No lease reached evaluation or finalisation. The worker continued after safety skips, supporting change 5 on the fresh-lease path only. It was stopped via SIGINT to the harness (exit 130, operator signal 2, no leftover owned PIDs, unrelated sleep survived). Two-model finalisation, footprint drop and cross-lease teardown remain unproven. |
| B3 task-group coverage | Unproven | No finalised records; lv/generative scope = 5 task groups per `api/worker/scope-policy.json` |
| B4 auth reuse | Pass | Restart: zero device-flow prompt lines; saved credential reused; bounded SIGINT stop clean |
| B5 interrupt/resume | Unproven | Needs a live evaluation; none started (queue contents) |
| B6 upload retry | Unproven | Needs a submitting lease with acks; none occurred; no-duplicate-request live check unproven (code path runtime.py:897-904 + unit tests only) |
| B7 oversized/unsupported | Unproven | No fixtures available (operator); not fabricated. Observed: safety-preflight failure path releases `unsafe_model` and the worker keeps running |
| B8 direct 7B | Pass | `Qwen/Qwen2.5-7B-Instruct` SST5 `--num-iterations 1` at `u`: exit 0, no stop, peak pressure 1, swap delta 0 MiB; util 0.57 logged; MCC 56.80%/62.19%, zero failed instances; one shutdown `Segfault encountered` after all scores (known diagnostic) |
| B9 docs | Pass with gaps | "Direct execution (no Docker)" followed literally; gaps: cp312-only Darwin pair not stated, npm/vercel steps of `make install` not mentioned, repeated unsafe_model re-leases not explained |
| B10 rows 3 / 4b | Pending deploy | `unattested` digest and no-re-lease decline not deployed; 4a dropped |

Known diagnostic: `Segfault encountered` (vLLM v0.30.0 shutdown) fires once per engine teardown; non-fatal in the direct run (exit 0). Whether the long-lived worker survives it across leases remains unproven because no lease reached engine start. No source changes were made; the tested clone is tracked-clean at the tested SHA. Evidence: `coord/2310`, `communication/2310/mac-results/part-b-3b88d131/`. This draft has not been posted to the issue.
