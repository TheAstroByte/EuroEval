# 506502fc: request a Mac run on the 24 GB and 64 GB Macs

**Branch:** `feat/2310-apple-gpu-worker` at `506502fc`, pushed to the fork. This
fast-forwards from the PR's earlier head `58f178e3`.

## What changed since Part B

| Commit | Change | Checked by this run |
|---|---|---|
| `de03da42`, `80fd3364` | Safety skips back off 30 s → 300 s; the count resets after a lease gets through | No (unit tests only; needs a live worker) |
| `ec4f38b3` | Worker tests no longer assume Linux | **Yes:** step 4 |
| `30c87b2d` | Broker declines ignore model-ID letter case | No (broker, pending deploy) |
| `c79c5e14`, `506502fc` | Docstring and docs wording | No |
| `728b3c54` | Before claiming, discovery refuses unless MLX can use Metal, vllm-metal's `metal` plugin is installed and not excluded by `VLLM_PLUGINS`, `VLLM_TARGET_DEVICE` is not `cpu`, and PyTorch MPS is available | **Yes:** step 3 |

## What to run

**No live worker.** Dan has not deployed the broker change yet, so do not start
`euroeval-worker`: each claim and release edits a public request issue. The script
never starts it.

One script does everything, on either Mac:
[`briefs/2026-11-27-mac-run.sh`](../briefs/2026-11-27-mac-run.sh). It uses the vetted
Part B harness, copied as [`briefs/mac-run-h.py`](../briefs/mac-run-h.py).

1. **Checkout.** A worktree of `~/Developer/EuroEval` at
   `~/Developer/worktrees/EuroEval/2310-mac-run-506502fc`, or a fresh clone at that path
   if there is no `~/Developer/EuroEval`. Then `make install`; press Enter at each
   `.env` prompt.
2. **Versions** and the native-extension check (expect `True` and the wheel URL).
3. **Apple GPU probe.** `discover_hardware()` three times, timed, checked against MLX's
   cap, `vm_stat` and `hw.memsize`. Then the two refusals: `VLLM_TARGET_DEVICE=cpu` and
   `VLLM_PLUGINS=none` must both refuse.
4. **Worker tests on macOS:** the five worker test files.
5. **Direct `euroeval` runs** under the harness. `u` is recomputed before each
   generative run (`d1.u.json`, `d2.u.json`), as the worker does before each evaluation:
   - `d1`: `Qwen/Qwen3-0.6B#no-thinking`, SST-5, 1 iteration;
   - `d2`: `Qwen/Qwen2.5-3B-Instruct`, SST-5, 1 iteration (skipped if `cap × u` is below
     9 GB);
   - `d3`: the encoder `jonfd/electra-small-nordic`, AngryTweets, 1 iteration, on the
     automatic device, which is MPS when available.
6. **Summary** in `summary.txt`, ending with a `failures:` line. The raw logs, samples
   and footprint captures are packed into `logs.tar.gz` and kept unpacked if the
   archive can't be verified. The script exits non-zero if anything failed.

If the probe fails, the tests still run but the direct runs are skipped. If the harness
stops a run (memory pressure or swap growth) or it is cancelled, the remaining runs are
skipped.

Results go to `mac-results/run-506502fc-<ram>gb/`. The script refuses to overwrite an
existing results folder.

## Pass criteria

| Step | Pass |
|---|---|
| 2 | `make install` exits 0; extension check `True`; vllm-metal from the wheel URL |
| 3 | `probe.json` has `"pass": true`; record `seconds` (the probe's cost per discovery). Both refusal lines show `"refused": true` |
| 4 | All tests pass. On a failure, report the test names; do not edit code |
| 5 | Each `d*` result: exit 0, `stop_reason` null, peak pressure ≤ 2, swap growth under 1 GiB, no leftover PIDs. Record `peak_footprint_mib` against `cap × u` from that run's `.u.json`, and any `Segfault encountered` lines |

A harness stop (pressure 4 or swap growth) is a result, not a failure to retry: report it.

## 64 GB Mac (local agent)

1. `git pull` the `coord/2310` branch.
2. Close heavy apps, then run `bash communication/2310/briefs/2026-11-27-mac-run.sh`
   from the `coord/2310` checkout.
3. Write `mac-results/run-506502fc-64gb/handoff.md`, at most 30 lines:
   - the pass/fail for each step;
   - the probe `seconds`;
   - for each `d*` run, the footprint as a percentage of `cap × u` and of `usable`;
   - anything unexpected.
4. Commit only that results folder, plus a one-line `STATUS.md` update, to `coord/2310`
   and push. Do not push to the feature branch, and do not post on GitHub.

## 24 GB Mac (operator, no agent)

The operator runs the script in Terminal on the host after stopping the Docker sandbox,
which otherwise holds several GB of memory. The implementation machine reads the results
folder afterwards and writes the handoff.
