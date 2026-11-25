# 72bd08c5: A1 review and request to run A2–A4

**Branch:** `feat/2310-apple-gpu-worker` at `72bd08c5`. There is no new commit.
**Answers:** `mac-results/gate-a-72bd08c5/` (coordination commit `f6412a45`).

## A1 memory control: passes, on arithmetic

The missing `metal_limit` log line is a mistake in the brief, not a failure of the code.
In vLLM 0.30.0 / vllm-metal 0.30.0, the default `paged_attention_layout_budget` path
(`vllm_metal/v1/cache_policy.py:954-968`) reads the cap and the fraction but logs only
the resulting KV budget. Those logged numbers are enough to check the denominator:

| Quantity | Value |
|---|---|
| MLX cap, from `u.json` | 55,662,788,608 B |
| `u`, logged as `--gpu-memory-utilization=0.55` | 0.5498 |
| cap × u | 30.60 GB |
| Logged KV budget | 28.57 GB |
| Remainder (model, profiled overhead, draft) | **2.03 GB** |

The 2.03 GB remainder agrees with Step 0, which measured 1.19–3.70 GB of model memory
for the same model. If the denominator were physical RAM, the remainder would be 9.21 GB,
which does not fit. So the runtime numbers show that vllm-metal applies the worker's `u`
to MLX's cap. That is the formula from change 1.

Together with pressure 1, 0 MiB swap growth and no `VLLM_METAL_MEMORY_FRACTION`, **A1 is
accepted**.

**Amended A1 criterion** for this and later runs, replacing "logs `metal_limit`":

- the log shows `Paged attention: using --gpu-memory-utilization=<u rounded>`;
- the log shows `Upstream cache layout: reporting <B> GB KV budget`;
- `cap × u − B` is between 0 and 5 GB for a model under 1B parameters.

Report the computed remainder.

## Teardown segfault: identified upstream, not yet known to matter

- **Origin.** vLLM v0.30.0 added `torch.accelerator.empty_host_cache()` to
  `cleanup_dist_env_and_memory()` (`vllm/distributed/parallel_state.py:2466-2471`).
  vLLM v0.27.1 does not have that call. It runs when the platform is not CPU, and the
  native trace (`TVMFFIEnvRegisterCAPI` → `at::accelerator::emptyHostCache()`) matches
  it.
- **Where it crashed.** It fired after `Metal worker shutdown complete`, in the vLLM
  engine-core shutdown path. EuroEval's `clear_vllm()` calls only
  `destroy_model_parallel()` and `destroy_distributed_environment()`.
- **Effect.** The main process carried on. It printed `Completed 2 benchmarks` and exited
  0, and no owned process was left behind.

**Why it still matters.** The volunteer worker runs every lease in one long-lived
process. Dan's acceptance criteria need two models evaluated one after the other, with
resources released in between. A1 loaded only one model, so it cannot show whether a
second model load works after this crash.

**Decision.** Do not patch it yet. The two-model switch in A4 is the cheapest test that
tells the cases apart:

- **The second model loads and scores in the same process:** record the crash as a
  known, non-fatal upstream shutdown diagnostic. An upstream issue can be drafted after
  operator approval.
- **The second load fails, hangs, or the process dies:** that blocks Gate A. Stop and
  report it with the full log. Do not work around it on the Mac.

## Requested Mac run

Use the same clone at `72bd08c5` and a **fresh `u`**. Write results to
`mac-results/gate-a-72bd08c5-a2a4/`. A1 does not need repeating.

1. **A2** (SST-5 and HellaSwag, 10 iterations, both shot modes) and **A3** (CoNLL with a
   per-mode `--debug` schema audit), with the brief's pass criteria.
2. **A4**, with the switch run first:
   - **Two-model switch:** pass criteria as in the brief. In addition, record whether
     the teardown segfault appears between the two models and whether the second model
     scores. **This decides the teardown question.**
   - Then SQuAD, CNN/DailyMail, the canary, and Ctrl-C.
3. **A1 criterion for each run:** check every new run's log against the amended criterion
   above.
4. **Every run:** record whether the teardown segfault appears in the log. Treat it as
   an observation, not a failure, unless it breaks something.
5. **Report:** use the brief's template, with the v0.30.0 paragraph. Reference A1 from
   `gate-a-72bd08c5` and this note.

Part B stays unauthorised until Gate A passes.
