# Part B handoff at 3b88d131128d49a4a141d15268acd88280a6b920

## What was run
- Fresh clone `/Users/daniel/Developer/EuroEval-2310-3b88d131` at the exact commit; `make install` exit 0 (`.env` prompts answered with Enter; `.env` never printed, copied or archived). Extension check `True`; vllm-metal 0.30.0 from the release wheel (`direct_url.json`).
- `RUN=/tmp/ee-2310-partB-3b88d131`, harness = the Gate A independent-footprint `h.py` (2 s guard, 3 s footprint cap, INT30/TERM10/KILL5 on the owned PGID only, refuses baseline pressure >= 2). Fresh `u=0.5687` computed once (u.json). Dedicated state dir `~/.euroeval-worker-2310`. `sleep 86400` probe PID 99782 recorded alive before and after each stop, then killed.
- B1 hardware: pass (details in summary.json / b1-hardware.json).
- B2: The complete worker log records 51 incompatible-model safety skips. All 15 sampled lease identities were thinkingmachines/Inkling-2-Mini (lv); the remaining skips have no model identity recorded. The sampled model has model_type inkling2_loop, unknown to Transformers 5.14.1. No lease reached evaluation or finalisation. The worker continued after safety skips, supporting change 5 on the fresh-lease path only. It was stopped via SIGINT to the harness (exit 130, operator signal 2, no leftover owned PIDs, unrelated sleep survived). Two-model finalisation, footprint drop and cross-lease teardown remain unproven.
- B4: restart as b4-worker, zero device-flow prompt lines, saved credential reused; bounded SIGINT stop clean. The log records active lease preservation before shutdown; resumable state remains in the dedicated local state directory.
- B8: direct `euroeval ... Qwen/Qwen2.5-7B-Instruct sst5 --num-iterations 1 --gpu-memory-utilization 0.5687`: pass (exit 0, no stop, pressure 1, swap delta 0 MiB, util 0.57 logged, MCC 56.80%/62.19%, 0 failed instances, one shutdown `Segfault encountered` after all scores, peak footprint 34,639 MiB).
- B9: docs followed literally; gaps in b9-docs.md.
- B3/B5/B6/B7: unproven (no lease reached evaluation; no fixtures per operator). B10: rows 3 and 4b pending deploy; 4a dropped.

## Bounds and guards held
- Every live run under the harness; per-stage MAX_RUN_SECONDS (b2: 21600, b4: 600, b8: 14400); total live time ~1.5 h (< 8 h). No worker left claiming leases; no owned PIDs remain; probe sleep killed only after alive evidence. No source/lock changes: clone tracked-clean at the tested SHA (package-lock.json churn from npm restored).

## Evidence layout

The top-level reports, diagnosis, hardware result and selected runtime results are available directly in this folder. `evidence.tar.gz` contains the complete sanitized run under `raw/`, including all logs, command arrays, memory samples, physical-footprint captures and redacted lease probes. `manifest.sha256` verifies those archived members after extraction; `evidence.tar.gz.sha256` verifies the archive.

The archived reports include the corrected skip count and sampling limits. Device-flow codes are redacted. No `.env`, worker state or credentials, model weights or bytecode are included.

## Next action

Part B acceptance is incomplete. A queue model compatible with Transformers 5.14.x is needed before another authorized run can test two-model finalization, cancellation/resume, upload retry and worker teardown across leases. Broker changes 3 and 4b still require deployment. No source workaround was made. The issue comment remains a draft.
