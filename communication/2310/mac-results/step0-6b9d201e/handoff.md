# EuroEval 2310 Mac spike handoff

The existing backend runs on this Apple Silicon Mac, but it is not ready to certify the worker's required features. The measurements identify a memory-control mismatch, classification fallback, malformed constrained outputs, and a registry that overstates Metal support. No implementation was made.

Read `comment.md` for the concise findings and complete task table. That comment is local and awaits the operator's review. Do not post it or create a PR from this handoff without the operator's instruction.

## Scope and source

Dan's issue is <https://github.com/EuroEval/EuroEval/issues/2310>. Its required route is the existing volunteer worker and EuroEval vLLM integration through vllm-metal. The previous GGUF PR 2308 is closed and is not the implementation path.

The experiment used a fresh upstream clone at commit `6b9d201edecdd7e2d744f7f04ba42ad1e714916d`. The supplied protocol was written against `1fd4035f`. The operator's original checkout was on `main` at `bd47b45bf114090d18e7ec3076038255a5919e84` and was left without tracked changes.

The installed plugin commit is `8a3ddf05b229a71234ffaabc225cd345edc4b68e`, and vLLM core is `6e448d0ea9bf3d88d898b65449ca6dc2aec170ac`. Their original metadata is in `vllm-metal-origin.json` and `vllm-origin.json`. Versions and hardware are in `s1-versions.txt` and `machine.txt`.

No live worker ran, and no leases or submissions were created. The only broker request was a public release-info GET. Authentication, broker eligibility, upload retries, resume, direct CUDA execution, and end-to-end worker operation remain untested.

## Memory control must reach the plugin

The current worker calculates CLI utilisation from usable memory and physical total memory at `src/euroeval_worker/runtime.py:659`. EuroEval passes that value into vLLM at `src/euroeval/benchmark_modules/vllm.py:1920`. The pinned Metal planner does not read that setting.

The plugin's paged path uses `VLLM_METAL_MEMORY_FRACTION`, defaulting to 0.9 of MLX's recommended working-set cap. It subtracts model memory and profiled overhead, then preallocates the remaining KV pool. Read `memory-source.txt` for numbered source extracts. The allocation code creates zero arrays and evaluates them eagerly.

Both observed cap candidates equal 55,662,788,608 bytes, or 51.8400 GiB, on this machine. Prefer MLX's `max_recommended_working_set_size` because that is the backend's actual denominator. It is a limit, not available memory. Availability was estimated from free plus inactive pages, with a 16,384-byte page size and no speculative-page double count.

The unchanged-default run allocated 47.98 decimal GB of KV for Qwen3-0.6B. It reached critical pressure and peak swap growth of 11,460.07 MiB. It was interrupted after one zero-shot bootstrap iteration. No OOM exception occurred, so the protocol's OOM-retry ladder was not triggered. Repeating the original CLI-only sweep would not reduce that planner's budget.

The controlled sweeps keep Metal fraction at 0.15 while varying CLI utilisation. Their startup logs show the same Metal fraction in all cases. KV size varies because the measured model-memory term varies, not because the logged fraction changes. All three complete normally without swap growth. Each uses one iteration in both shot modes.

The corrected budget test used a fresh idle availability estimate of 36.7822 GiB:

```text
usable = min(51.8400 GiB, 36.7822 GiB - 1 GiB) = 35.7822 GiB
existing CLI calculation = 0.8 * usable / 64 GiB = 0.4472780227661133
actual Metal fraction = 0.8 * usable / 51.8400 GiB = 0.5521949663079302
```

Applying the Metal fraction explicitly passed SST-5, a two-model switch, and CNN/DailyMail startup plus generation before interruption. These runs stayed at normal pressure without swap growth. The 1 GiB headroom has empirical support for these small-model trials with the corrected control. It is not a validated universal reserve for larger models or all contexts. Full task coverage used fraction 0.15, not the larger corrected fraction.

The plugin caches its environment-derived configuration on first access. Any dynamic setting must reach the relevant process before that access. Merely updating the environment after `get_config()` has populated its global cache is insufficient. Preserve the existing worker execution machinery when choosing where to apply the budget.

RSS is unsuitable as the inference-memory measure. In the corrected SST-5 run, sampled aggregate RSS peaked at 3,697.6 MiB while sampled aggregate footprint reached 38,679.4 MiB. These are separate sampled maxima, not simultaneous measurements or a decomposition of system physical memory. MLX/model/cache measurements and OS pressure remain necessary.

## Required inference features have concrete gaps

All full dataset runs use the required `Qwen/Qwen3-0.6B#no-thinking` selector and all common protocol flags. They retain ten bootstrap iterations in both shot modes. Logs identify `VLLMModel`, instruction-tuned mode, and MLX GPU execution. No classification or NER run identifies the model as a reasoning model.

SST-5 and HellaSwag request logprobs, then report a word-edit-distance fallback. That fails the supplied feature criterion even though scores are printed. The observed warning comes from `src/euroeval/task_group_utils/sequence_classification.py:385`. The logs do not establish whether the root cause is token decoding, label extraction, generated output, or upstream sampling. Do not describe logprobs as unsupported in every case based on this evidence.

CoNLL requests the logged JSON schema. The preserved cache has 1,454 unique completions. Strict JSON decoding rejects 129. EuroEval's more tolerant extraction rejects 119. All 1,325 strict JSON completions satisfy the schema. These counts are cache-entry counts, not counts across bootstrap samples. Concrete malformed examples include `{"person": [],≧` and values containing unrelated text outside JSON syntax.

Use these artifacts to inspect the failure:

- `conll-model-outputs.json` contains the preserved completions and predictions.
- `conll-invalid-examples.json` records EuroEval parser failures and examples.
- `conll-schema-audit.json` records the exact requested schema and the strict audit.
- `analyse-conll.py` and `audit-conll-schema.py` reproduce those checks.
- `s2-capped-A-conll-en.log` records the requested schema and scoring failures.

The parser reports the failure at `src/euroeval/task_group_utils/token_classification.py:298`. The source of malformed constrained generation remains unlocalised between EuroEval decoding/integration and the upstream backend. Do not treat a structured-request log line or a printed score as proof that every output followed the schema.

SQuAD and CNN/DailyMail complete both shot modes with zero reported failed instances. The contamination canary meets the exact criterion, `status=collected, count=256`.

## Switching and cancellation

The initial switch test used CLI utilisation 0.8 and Metal fraction 0.15. Both architectures loaded and scored. The strict gap footprint was missed on that first run; the manual transition capture happened after B's load announcement and is not used as the gap result.

The repeat used CLI 0.447278 and Metal fraction 0.552195, one bootstrap iteration per shot mode, four completed benchmarks, and exit 0. Qwen3 and SmolLM2 both loaded and scored. SmolLM2's MCC was 0.00 in each mode, so this establishes lifecycle execution rather than model quality or classification-feature correctness.

The repeat's sampled aggregate footprints are 31,654 MiB during A, 29,062 MiB in the immediate teardown gap, and 31,644 MiB during B. The gap observer proves B's load announcement had not appeared before or after the capture. A's engine was still present at that early teardown moment. Do not interpret the gap as a steady, fully reclaimed memory baseline or infer a leak from that single sample.

The two-second process samples observe A's engine last at 08:45:58 UTC and B's first at 08:46:10 UTC, with no sampled overlap. See `s4-verified-engine-lifetimes.json`, `s4-verified-gap-observer.json`, and `s4-verified-two-models-footprints.json`.

Cancellation used the same corrected budget. The harness waits for a nonzero completed CNN/DailyMail generation count, then sends one SIGINT to its own process group, matching terminal Ctrl-C delivery. It tracks only descendants of the process it started. No owned processes remain after 5 seconds or 30 seconds. The Metal worker reports shutdown; pressure stays normal and swap does not grow. The aborted CLI exits 1, which is the observed cancellation exit status, not a failed inference exception.

Read `s4-interrupt-verified-result.json` for exact owned PIDs and the audit. This does not validate the volunteer worker's lease release, credential preservation, or resumable state because no live worker was started.

## Registry filtering needs a backend failure path

`ModelRegistry.get_supported_archs()` advertises 367 architectures. It includes `MambaForCausalLM`, which also appears in the public checkpoint config saved as `s5-model-config.json`.

`state-spaces/mamba-130m-hf` downloads and loads its model weights, then fails in vllm-metal's dimension adapter after 48.35 seconds. The exception is at `vllm_metal/v1/model_lifecycle.py:240`. This is a backend architecture gap, not an OOM, download, or installation failure. The exact exception and full traceback are in `s5-unsupported.log` and its event extract.

EuroEval wraps the failure as a generic `InvalidModel` at `src/euroeval/benchmark_modules/vllm.py:2271`. The implementation must ensure that the intended unsupported-model decline path can categorise this backend failure and prevent repeated leases. The registry alone cannot establish Metal compatibility.

The standalone registry-import probe also logs a ByteLevel tokenizer compatibility-patch warning caused by a circular import. That warning is preserved in `s5-archs-stderr.txt`. It is an observation from that probe, not an established explanation of the classification or JSON failures.

## Reproduction and remaining acceptance work

The supplied procedure is retained as `request.md`. Commands ran from `/Users/daniel/Developer/EuroEval` on the Mac. On another machine, use its own clone path and environment. Do not copy the Mac virtual environment.

The `ee` wrapper contains all common flags. `run-next.sh` records the controlled sweeps and full task runs. `planned-budget.py 1` records the corrected headroom test. `verified-switch.py` and `observe-gap.py` record the repeat switch. `interrupt.py verified` records cancellation. The older `run-preinstall-budget.sh` is an unused alternative calculation and was not executed.

The public broker release-info response reports 18.4.0.dev0. The installed package reports 18.4.0.dev. Both normalise to 18.4.0 under the broker's exact rule. This checks version compatibility only, not an upload.

Before calling issue 2310 complete, the implementation still needs real worker evidence for authentication reuse, conservative hardware reporting and eligibility, two leased models, unsupported-model decline, upload retry, resume, cancellation state, direct CUDA, and the existing Docker/CUDA route. The observed inference-feature gaps must be resolved and rerun through the existing backend.

The closed local GGUF branch was removed after a recovery bundle was saved separately. Its old temporary llama.cpp build and probe workspace were moved to Trash. Shared model caches and unrelated inference applications were preserved. The implementation archive excludes the old branch bundle, model weights, virtual environments, and `.env` files.
