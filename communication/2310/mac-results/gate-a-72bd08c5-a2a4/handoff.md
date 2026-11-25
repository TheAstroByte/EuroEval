# Gate A continuation at 72bd08c5

Gate A passes under the amended A1 criterion, with a known non-fatal upstream shutdown diagnostic. A2–A4 were run at the exact requested commit. Part B was not run.

Pins on Darwin: vLLM 0.30.0+cpu / vllm-metal 0.30.0 release wheel, MLX 0.32.1, Transformers 5.14.1, torch 2.13.0.

## Decision and limits

The same CLI parent completed four SST-5 benchmarks across Qwen and SmolLM2. One native shutdown diagnostic occurred before SmolLM2 was announced. SmolLM2 then loaded and scored both shot modes. The first engine exited and its owned-group physical footprint fell before the next model loaded. The tested teardown diagnostic therefore does not block this gate. No backend workaround was added. Worker leases, broker behavior and long-running worker acceptance remain untested.

A1 from the preceding bundle was accepted by [the implementation-machine review](../../implementation-notes/2026-11-25-72bd08c5-a1-review-and-a2-a4-request.md). The current run applies that amended arithmetic check to each new invocation. The old bundle remains unchanged.

## Per-run evidence

| Command | Exit / stop | KV budget GB | Remainder GB | Shutdown diagnostics | Peak footprint MiB |
|---|---|---|---|---|---|
| a2-sst5 | 0 / none | 31.27 | 2.03 | 1 | 36,157 |
| a2-hellaswag | 0 / none | 31.27 | 2.03 | 1 | 35,995 |
| a3-conll-zero-shot | 0 / none | 31.27 | 2.03 | 1 | 34,966 |
| a3-conll-few-shot | 0 / none | 31.27 | 2.03 | 1 | 37,752 |
| a4-switch | 0 / none | 31.27, 31.76 | 2.03, 1.54 | 2 | 35,705 |
| a4-squad | 0 / none | 31.27 | 2.03 | 1 | 35,556 |
| a4-cnn-dailymail | 0 / none | 31.27 | 2.03 | 1 | 36,820 |
| a4-canary | 0 / none | 31.27 | 2.03 | 1 | 34,036 |
| a4-interrupt | 1 / operator signal 2 | 31.27 | 2.03 | 1 | 36,031 |

All runs stayed at pressure 1 with 0 MiB swap growth, and all ended with no owned PIDs. Footprints are sums of physical footprints sampled independently of the memory guard. They are sampled observations, not exact simultaneous peaks. The Ctrl-C run intentionally interrupts generation, so its nonzero exit and missing full benchmark scores are expected.

The switch observer measured 35454.904 MiB at shutdown and 1156.394 MiB after the first engine exited. Both captures finished before SmolLM2 was announced or loaded. The EuroEval parent PID stayed 59445. See `a4-switch.transition.json` and its raw footprint files in the archive.

A2 recorded both logprobs and structured generation for each dataset and zero fallback messages. Both shot modes ran ten iterations per dataset. A3 used complete debug caches copied separately for each mode; cache cardinality is unique prompts, not total bootstrap samples. SQuAD and CNN/DailyMail each ran ten iterations per shot mode and reported zero failed instances. The canary reported collected count 256. A5 was not triggered because A2 and A3 passed.

## Reproduce and transfer

- [summary.json](summary.json) contains every runtime result, budget calculation, audit, switch decision and cancellation result. Exact command arrays are preserved in the archive as `*.start`.
- [Issue comment draft](issue-comment-draft.md) follows the report template and contains the required pins paragraph verbatim. It has not been posted.
- [evidence.tar.gz](evidence.tar.gz) contains raw logs, sampled memory, raw footprints, complete CoNLL caches, the strict auditor, temporary instrumentation and the supplied briefs. [evidence.tar.gz.sha256](evidence.tar.gz.sha256) verifies the archive. The internal `manifest.sha256` verifies its members.
- No model weights, `.env`, worker credentials or worker state are included. The tested clone remained tracked-clean. Debug artifacts were left in place and copied for transfer.
- Fresh `u.json` is reused across every invocation. The legacy fraction variable was absent. Each footprint call is limited to three seconds, with footprint sampling independent of the two-second pressure/swap guard.
- The source and lock files were unchanged; only coordination evidence is published. No issue comment or upstream issue was filed.
