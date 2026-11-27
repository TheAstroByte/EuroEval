# 24 GB Mac run at `506502fc`: handoff

Written by the implementation machine from this folder; the operator's Cursor session ran
the script and the d2 rerun.

**Machine:** Apple M4 Pro, 24 GB (25,769,803,776 B), macOS 27.2.1 (26B131). Background
management software left only 10.8–13.8 GB available. The Docker sandbox was stopped.

**Outcome:** the script exited 0 with `failures: none`. The script skipped d2, because
its 9 GB budget threshold was stricter than the broker's memory-fit rule. d2 was then rerun
alone in `d2-rerun/` and passed.

## Results per step

- **make install:** exit 0 in 442 s. The native extension check printed `True`, and
  vllm-metal 0.30.0 came from the release wheel URL. The versions match the 64 GB run;
  Python is 3.12.16.
- **Probe:** `pass: true`. One `metal-0` GPU; the total equals MLX's cap of
  19,069,665,280 B; free is within 2%; `ram_bytes` equals `hw.memsize`. It took
  **10.44, 8.31 and 4.13 s**, against 5.15, 0.55 and 0.54 s on the 64 GB Mac. This led
  to `06be2c1a`, which probes once per worker process.
- **Refusals:** `VLLM_TARGET_DEVICE=cpu` and `VLLM_PLUGINS=none` were both refused, with
  their specific messages.
- **Worker tests:** 176 passed in 25.95 s.

## Direct runs

| Run | u | Plan `cap × u` | Sampled peak aggregate footprint | Of plan | Of usable | Min available | Pressure, swap growth | Result |
|---|---|---|---|---|---|---|---|---|
| d1 Qwen3-0.6B, SST-5 | 0.4084 | 7,427 MiB | 11,520 MiB | 155.1% | 124.1% | 4.3 GiB | 1, +0 MiB | exit 0, macro-F1 41.0 / 58.2 |
| d2 Qwen2.5-3B, SST-5 (rerun) | 0.5352 | 9,733 MiB | 14,457 MiB | 148.5% | 118.8% | 2.7 GiB | 1, +0 MiB | exit 0, macro-F1 54.7 / 71.0 |
| d3 electra-small-nordic, AngryTweets | n/a | n/a | 3,505 MiB | n/a | n/a | 10.3 GiB | 1, +0 MiB | exit 0, 0 failed instances |

- **Overshoot above plan:** 4,093 MiB for d1 and 4,723 MiB for d2. On the 64 GB Mac it
  was 3,642 and 4,706 MiB. It was similar in absolute terms in all four runs, so on
  24 GB it exceeds the 0.8 factor's margin. Pressure stayed normal and swap did not
  grow. These runs don't show where the extra memory came from.
- **d2 passes the broker's memory-fit rule on this Mac.** The worker reported 12.79 GB
  free, and 0.8 × 12.79 GB is 10.23 GB. That covers weights × 1.35 = 8.3 GB, using about
  6.2 GB of weights estimated from 3.09 B bf16 parameters. The weight files were not
  measured, and the broker's other eligibility rules were not checked.
  The vllm-metal log shows a 2.78 GB KV budget and 4,720 blocks.
- **Shutdown diagnostic:** one `Segfault encountered` line after scoring in d1 and in d2,
  the known upstream diagnostic.
- **Encoder device:** not logged by EuroEval. The probe confirmed MPS is available, and
  EuroEval selects MPS whenever it is.

## Not covered

No live worker was run and no broker was contacted. Macs below 24 GB are untested.
