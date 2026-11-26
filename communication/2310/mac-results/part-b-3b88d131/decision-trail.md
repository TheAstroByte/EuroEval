# Part B decision trail — 3b88d131128d49a4a141d15268acd88280a6b920
- RUN=/tmp/ee-2310-partB-3b88d131 (fresh). Clone /Users/daniel/Developer/EuroEval-2310-3b88d131 at exact 3b88d131. make install exit 0.
- Extension check True; vllm-metal from v0.30.0 release wheel URL. u=0.5687 (available 40639905792, cap 55662788608, usable 39566163968).
- S=~/.euroeval-worker-2310 (fresh, was absent). UNRELATED sleep86400 PID 99782.
- Total live-run budget < 8h. Per-stage MAX_RUN_SECONDS set on each harness run. Stop conditions: pressure>=4 or swap growth >1GiB (harness guard), baseline pressure>=2 refuses, second lease death after teardown diagnostic = blocker.
## Checkpoints
start_epoch 1795672460
- 06:55 first device flow expired unapproved (request_secret transport broken in this harness; sign-in requested via thread message + question widget instead; code kept out of logs). Worker exited 1, no leftovers.
- 07:12 second device flow approved by user; worker authenticated as TheAstroByte 07:21:16; credential saved in S (credential_present=true).
- 07:23+ broker repeatedly leases thinkingmachines/Inkling-2-Mini (lv); every lease fails worker safety preflight "not compatible with the installed Transformers stack" -> released unsafe_model; worker keeps running (change 5 fresh path verified live, N skips so far). No engine ever started, so no Segfault diagnostic observed yet. 4b pending deploy => broker re-leases same model.
- B2 two-different-models-finalised criterion blocked by queue contents so far; bounded watch until ~08:50 (watcher), then decision.
