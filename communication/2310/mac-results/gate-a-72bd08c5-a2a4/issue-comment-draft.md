Gate A passes at `72bd08c5cbebbb804f985ee192ffc8bc9b9579a8` on M3 Max, 64 GiB, macOS 27.0.1, with a known non-fatal upstream shutdown diagnostic.
Pins on Darwin: vLLM 0.30.0+cpu / vllm-metal 0.30.0 release wheel, MLX 0.32.1, Transformers 5.14.1, torch 2.13.0.

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

Fresh `u=0.5983`: available 42,701,389,824 B, MLX cap 55,662,788,608 B, usable 41,627,648,000 B. No legacy Metal fraction override. cap × u = 33.303 GB.

| Item | Result | Evidence |
|---|---|---|
| A1 memory | Pass by amended criterion | Prior A1 accepted in the implementation-machine review; not repeated. Every new run logs utilization 0.60 and a KV budget leaving 0–5 GB. Qwen leaves 2.03 GB, SmolLM2 1.54 GB. |
| A2 SST-5 / HellaSwag | Pass | 10 iterations per shot mode, both strategies logged, zero label fallbacks and failed instances. |
| A3 CoNLL | Pass | 10 iterations per mode; strict schema audit: zero-shot 252 unique outputs, few-shot 1,608; zero invalid JSON or schema violations. |
| A4 switch | Pass | Same CLI parent; Qwen teardown diagnostic precedes SmolLM2 loading and both scores. Four benchmarks complete. Physical footprint falls from 35,455 to 1,156 MiB before the second model loads. |
| A4 SQuAD / CNN-DailyMail | Pass | 10 iterations in both shot modes; no failed instances. |
| A4 canary | Pass | `status=collected, count=256`. |
| A4 Ctrl-C | Pass | One SIGINT to harness after generation progress; `operator signal 2`, no owned PIDs remain. |
| A5 reduced reproduction | Not triggered | A2 and A3 pass. |
| Part B | Not run | Explicitly excluded from this request. |

All completed commands exit 0; peak pressure 1, swap growth 0 MiB, no owned PIDs remain. The intentional Ctrl-C exit is recorded separately.
`Segfault encountered` appears at engine shutdown. The switch demonstrates it is non-fatal for this test; no teardown patch was made. This does not prove worker lease acceptance.
Evidence and per-run diagnostics: `coord/2310`, `communication/2310/mac-results/gate-a-72bd08c5-a2a4/`. This draft has not been posted to the issue.
