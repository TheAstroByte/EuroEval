# 64 GB Mac run at `506502fc` — handoff

Machine: Apple M3 Max, 64 GiB (68,719,476,736 B), macOS 27.0.1 (26A434), memory pressure 1 at start.
Script: `communication/2310/briefs/2026-11-27-mac-run.sh`, target `506502fcc4de6c4f4e842c1ebc2d7ba178ea0157`.
Outcome: `SCRIPT_EXIT=0`, `failures: none`. Checkout: `~/Developer/worktrees/EuroEval/2310-mac-run-506502fc` at the exact SHA, tracked files clean except npm's `package-lock.json` churn (evidence in `package-lock-churn.diff`; not restored, not staged).

## Results per step

- **make install**: exit 0 in 9 s; native extension check `True`; vllm-metal 0.30.0 from the official v0.30.0 wheel URL. Versions: euroeval 18.4.0.dev, vllm 0.30.0+cpu, mlx 0.32.1, mlx-lm 0.32.0, torch 2.13.0, transformers 5.14.1, huggingface-hub 1.33.0, python 3.12.13.
- **Probe** (`probe.json`): `pass: true`, seconds `[5.15, 0.55, 0.54]`; one GPU `metal-0` (Apple M3 Max), total = MLX cap 55,662,788,608 B, free within 2% of expected, ram = `hw.memsize`.
- **Refusals** (`refusals.txt`): `VLLM_TARGET_DEVICE=cpu` and `VLLM_PLUGINS=none` both `"refused": true`.
- **Worker tests**: 176 passed in 21.42 s (the five worker test files).
- **d1** `Qwen/Qwen3-0.6B#no-thinking`, SST-5, 1 iteration: exit 0, `stop_reason` null, peak pressure 1, swap +0 MiB, no leftover owned PIDs. u=0.5557 (cap×u = 29,499 MiB, usable = 36,876 MiB); peak footprint 33,141 MiB = **112.3% of cap×u**, **89.9% of usable**. Macro-F1 40.13% zero-shot / 59.39% few-shot, 0 failed instances; 1 `Segfault encountered` line (known non-fatal upstream teardown diagnostic).
- **d2** `Qwen/Qwen2.5-3B-Instruct`, SST-5, 1 iteration (budget 36.6 GB ≥ 9 GB, not skipped): exit 0, stop null, peak pressure 2, swap +0 MiB, no leftovers. u=0.6584 (cap×u = 34,951 MiB, usable = 43,687 MiB); peak footprint 39,657 MiB = **113.5% of cap×u**, **90.8% of usable**. Macro-F1 55.54% zero-shot / 71.04% few-shot, 0 failed instances; 1 `Segfault encountered` line.
- **d3** `jonfd/electra-small-nordic`, AngryTweets, 1 iteration: exit 0, stop null, pressure 1, swap +0, no leftovers. Peak footprint 3,394 MiB — **no cap×u denominator applies (encoder run), N/A**. Macro-F1 40.22%, MCC 0.2707, 0 failed instances. The automatic device is not logged, so MPS is **unproven** from the log.

## Evidence and notes

- `logs.tar.gz`: 143 members, all verified by extraction, zero `._` AppleDouble entries; sha256 in `logs.tar.gz.sha256`.
- Full orchestrator stdout (secret-scanned, clean): `orchestrator.log`.
- No live worker started, no broker requests, no euroeval-worker, no queue admin, no GitHub posts, no source edits, no commits by this run.
- Harness guard independently verified in `h.py`: 2 s memory sampling, footprint snapshots in a separate thread with 3 s timeouts (≤6 PIDs), owned-process-group-only cleanup, baseline pressure ≥ 2 refusal, per-run time limits.
