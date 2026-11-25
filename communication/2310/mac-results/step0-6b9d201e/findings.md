## Step 0 findings: vllm-metal on Apple Silicon

Machine: Apple M3 Max, 64 GiB RAM, macOS 27.0.1, native arm64 Python 3.12.13.
EuroEval @ `6b9d201edecdd7e2d744f7f04ba42ad1e714916d`: euroeval 18.4.0.dev,
vllm 0.27.1+cpu, vllm-metal 0.2.0, mlx 0.31.2, torch 2.13.0, transformers 5.14.1.
Logs confirm `MLX device set to: Device(gpu, 0)` despite the vLLM package's `+cpu` suffix.

Install: `make install` installed Rust automatically and completed after retrying the
blank `.env` answers through stdin, following an initial EOFError. Existing Command
Line Tools compiled the native Metal extension. No manual prerequisite fix was needed.

Task coverage uses `Qwen/Qwen3-0.6B#no-thinking`, ten iterations and both shot modes.
After the default-memory run reached critical pressure, all full coverage runs used
`VLLM_METAL_MEMORY_FRACTION=0.15`, CLI utilisation 0.8. These are diagnostic passes/gaps,
not unchanged-default acceptance results. Scores below are zero-shot / few-shot.

| Task group | Dataset | Result | Required feature evidence | Wall time |
|---|---|---|---|---|
| sequence_classification | sst5 | MCC 38.48 / 54.65%; feature gap | Logprobs + structured labels requested; word-edit-distance fallback observed | 364.26 s |
| multiple_choice_classification | hellaswag | Accuracy 31.72 / 37.50%; feature gap | Logprobs requested; word-edit-distance fallback observed | 341.12 s |
| token_classification | conll-en | F1 without MISC 30.64 / 36.37%; feature gap | JSON schema requested; 129/1,454 unique cached completions invalid strict JSON; EuroEval parser rejects 119 | 414.30 s |
| question_answering | squad | F1 59.51 / 58.32%; completed | Free generation; no failed instances | 225.57 s |
| text_to_text | cnn-dailymail | ChrF4++ 44.53 / 43.10%; completed | Long generation; no failed instances | 1,033.48 s |
| contamination canary | contamination-detection | status=collected, count=256 | Exact required status/count observed | 34.08 s |

No classification/NER run logged "is a reasoning model". Highest completed CLI utilisation: 0.8 with the explicit 0.15 Metal fraction.
The uncapped 0.8 baseline was interrupted, not an OOM exception or a completed pass.
Memory inputs: total 64 GiB; page size 16,384 B; torch.mps and MLX working-set caps
both 51.8400 GiB. Fresh idle host_available estimate: 36.7822 GiB, using free + inactive.
The pinned Metal planner ignores `gpu_memory_utilization`. It uses its own fraction
of MLX's cap, default 0.9, subtracts model memory and profiled overhead, then eagerly
allocates the remainder as KV cache (`vllm_metal/v1/cache_policy.py:695,754,766`;
`metal_kernel_backend/cache.py:154,156`). It does not preallocate the whole budget as KV.

Controlled sweep: one iteration per shot mode, Metal fraction fixed at 0.15.
RSS is aggregate evaluator + engine RSS, not physical footprint. Footprint is sampled
per-process and summed. RSS samples are every 2 s; footprint samples approximately 15 s.
Allocation uses decimal GB; RSS/footprint/swap use MiB; availability uses GiB.

| CLI util | KV allocation | peak aggregate RSS | sampled peak footprint | min host_available | pressure | swap delta |
|---|---|---|---|---|---|---|
| 0.3 | 3.81 GB | 3,874.8 | ~9,124 | 36.47 | 1 | -577.94 |
| 0.5 | 6.32 GB | 4,326.4 | ~14,438 | 31.34 | 1 | -256.00 |
| 0.8 | 3.81 GB | 4,236.4 | ~10,721 | 35.80 | 1 | -80.06 |

The logged fraction stayed 0.15; model-memory profiling varied between 1.19 and 3.70 GB.
The default baseline instead allocated 47.98 GB KV, reached pressure 4, minimum available
0.3134 GiB, and peak swap growth 11,460.07 MiB. Its engine footprint was unobserved.

Planned formula with 1 GiB headroom: usable 35.7822 GiB -> CLI util 0.447278.
That CLI value alone cannot enforce the budget. Applying Metal fraction
`0.8 * usable / MLX_cap = 0.552195` completed SST-5: pressure 1, swap delta 0,
minimum available 8.65 GiB; peak aggregate RSS 3,697.6 MiB versus footprint 38,679.4 MiB.
Recommendation: use MLX's cap because it is the planner's denominator. Headroom 1 GiB
passed these small-model trials with the corrected control; broader models remain untested.
`runtime.py:659` needs Metal-specific budget application, not only its current CLI scaling.
Metal config is cached on first access (`vllm_metal/config.py:148-156`).

Two models at CLI 0.447278 / Metal fraction 0.552195: both loaded and scored; 112.27 s.
Sampled aggregate footprint A -> early teardown gap -> B: 31,654 -> 29,062 -> 31,644 MiB.
The gap was captured before B's load announcement, while A's engine was still exiting.
No overlap of the two engine PIDs was observed in the 2 s process samples.
Ctrl-C during CNN/DailyMail generation at the same settings: no owned processes after 5 s or 30 s; pressure 1 and no swap growth. No live broker work was claimed.

Registry: 367 advertised architectures include `MambaForCausalLM`.
`state-spaces/mamba-130m-hf` loaded its weights, then failed after 48.35 s: registry gap.
Upstream `vllm_metal/v1/model_lifecycle.py:240` raises:
`ValueError: Cannot resolve model dimensions: num_kv_heads (num_key_value_heads / n_kv_heads), head_dim. Available keys: ['conv_kernel', 'hidden_size', 'intermediate_size', 'mixer_rms_eps', 'model_type', 'num_hidden_layers', 'state_size', 'tie_word_embeddings', 'time_step_rank', 'use_bcdt_rms', 'use_bias', 'use_conv_bias', 'vocab_size']`
EuroEval wraps it as generic `InvalidModel` at `src/euroeval/benchmark_modules/vllm.py:2271`.

Version: installed 18.4.0.dev vs broker 18.4.0.dev0 both normalise to 18.4.0: compatible.
Implementation gaps: actual Metal budget control; classification fallback at
`src/euroeval/task_group_utils/sequence_classification.py:385`; malformed constrained
output reported at `src/euroeval/task_group_utils/token_classification.py:298`; registry
over-advertising and preserving a categorisable backend failure. Classification/NER root causes remain unlocalised between EuroEval and upstream. No code changes or PR.
