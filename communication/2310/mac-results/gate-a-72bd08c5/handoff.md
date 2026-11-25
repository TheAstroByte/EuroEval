# Gate A rerun at 72bd08c5

The release wheel fixes the missing native-extension startup blocker. A1 completes scoring with safe measured memory behaviour, but Gate A remains not passed: the required `metal_limit` log evidence is absent, and a native shutdown segfault diagnostic appears despite the outer CLI exiting 0. Dependent A2-A4 checks remain unproven and were not run.

Read `comment.md` for the draft issue comment. It retains the operator's required v0.30.0 rationale verbatim immediately after the pins line. This run has not been posted to the issue.

## Provenance and setup

The coordination task was read from `coord/2310` at `acf5e985`. It requests a fresh Gate A run of `feat/2310-apple-gpu-worker` at `72bd08c5cbebbb804f985ee192ffc8bc9b9579a8` in `TheAstroByte/EuroEval`.

A fresh clone was created at `/Users/daniel/Developer/EuroEval-2310-72bd08c5`. `make install` completed on its first attempt in 11.531 seconds with blank prompt answers. No lock repair or implementation change was needed. npm's generated package-lock diff was retained and the tracked file restored.

The machine is Apple M3 Max, 64 GiB, macOS 27.0.1, native arm64 Python 3.12.13. Installed versions are vLLM 0.30.0+cpu, vllm-metal 0.30.0, MLX 0.32.1, mlx-lm 0.32.0, Transformers 5.14.1 and torch 2.13.0. Logs show MLX GPU execution.

The requested native-extension check printed `True`. Direct URL metadata points to the v0.30.0 release wheel, rather than Git. That metadata has an empty `archive_info`, so a hash cannot be read from it. The exact wheel was downloaded separately and its SHA-256 matched `3955de8b2c75b633ef889b70fa469a4db661a0c5bb2f78e36272d68b16da9353`. The installed `_paged_ops.cpython-312-darwin.so` matched the downloaded wheel's member byte for byte. See `wheel-check.json`, `vllm-metal-origin.json`, and `versions-and-extension.txt`.

Neither `VLLM_METAL_BUILD_FROM_SOURCE=1` nor `VLLM_METAL_MEMORY_FRACTION` was used. The downloaded wheel is omitted from the evidence archive; the verification metadata is retained.

## A1 observations

A fresh no-evaluation snapshot produced the persisted `u=0.5498`:

```text
available = 39,326,466,048 bytes
cap       = 55,662,788,608 bytes
usable    = 38,252,724,224 bytes, after reserving 1 GiB
u         = round(0.8 * usable / cap, 4)
```

A1 used `Qwen/Qwen3-0.6B#no-thinking`, SST-5, one iteration in both shot modes, and every common protocol flag. Its exact command and baseline are in `a1-memory.start`.

The plugin loaded native Metal kernels, logged CLI utilisation as 0.55 after rounding, and reported 28.57 GB of KV budget. Both shot modes scored: MCC 28.91% and 56.41%. The pilot log requested logprobs and structured labels and contained no word-edit-distance fallback. This is one iteration per mode, so it does not establish A2's ten-iteration feature criterion.

`a1-memory.result.json` records:

- outer exit 0 and `stop_reason: null`;
- peak pressure 1 and swap growth 0 MiB;
- minimum estimated available memory 12.1407 GiB;
- sampled peak aggregate footprint 33,411.7 MiB;
- no owned PIDs left and no harness error.

These runtime and safety conditions pass. The full A1 contract does not: `metal_limit` has zero matches in the log.

The default upstream cache-layout mode calls the MLX cap lookup and computes the budget at `vllm_metal/v1/cache_policy.py:954-968`, but its logger prints only the resulting KV budget. `_memory_fraction` reads vLLM's `gpu_memory_utilization` at lines 1040-1047. `_metal_limit_bytes` reads MLX's recommended working-set size at lines 1049-1059. The source explains the missing log field; it is not additional runtime observation of the cap variable. The implementation machine should reconcile the acceptance check with this logging path rather than treat the absent field as proof of a bad memory value.

## Native teardown diagnostic

After `Metal worker shutdown complete`, the log prints:

```text
!!!!!!! Segfault encountered !!!!!!!
  File "<unknown>", line 0, in TVMFFIEnvRegisterCAPI
  File "<unknown>", line 0, in at::accelerator::emptyHostCache()
```

The remaining native stack is preserved in `shutdown-diagnostic.txt`. The outer CLI then prints `Completed 2 benchmarks`, warns of one leaked semaphore, and exits 0. The guard still observes no surviving owned processes. A zero outer exit therefore does not establish clean native teardown.

The faulting process and native root cause were not experimentally isolated. The installed vLLM source contains a matching `torch.accelerator.empty_host_cache()` call at `vllm/distributed/parallel_state.py:2467`, but the native trace alone does not prove that source line caused the fault. `upstream-source-excerpts.txt` preserves this source lead and the cache-budget code. No code patch, monkeypatch, environment workaround, or extra crash reproduction was attempted.

## Gate boundary and next action

The brief requires stopping when A1 does not pass. A2-A4 were not run. A5's reduced feature reproduction requires A1 to pass and A2 or A3 to fail, so that conditional path was not entered. No upstream issue was filed.

The next implementation handoff is to resolve the runtime cap-evidence requirement and investigate the teardown diagnostic. A new Mac run follows the operator's next task. Part B, the live worker, authentication, claims, uploads and broker fixtures remain unrun.

The current Gate A harness was copied from the preceding Gate A attempt, not Step 0. It uses only RUN and the current working directory. Footprints run independently of the two-second memory guard, each with a three-second timeout. The safety conditions and INT/TERM/KILL group cleanup remain unchanged. All evaluation processes have exited.

## Evidence index

- `request.md`, `brief-updates.md`, and `implementation-note.md` are the instructions used.
- `install.log`, `versions-and-extension.txt`, `wheel-check.json`, and `vllm-metal-origin.json` record setup.
- `u.json` is the single persisted memory calculation for this attempt.
- `a1-memory.log` is the complete raw run, including the teardown diagnostic.
- `a1-memory.events.txt` extracts the important events and score lines.
- `a1-memory.result.json`, `a1-memory.samples.json`, and `a1-memory.footprints.json` record measured results.
- `a1-memory.footprint-*.txt` contains bounded raw per-process footprint captures.
- `summary.json`, `decisions.md`, and `upstream-source-excerpts.txt` preserve the outcome and interpretation limits.
- `h.py` and `audit.py` preserve the instrumentation. The CoNLL auditor was not run.

The archive excludes `.env`, worker state, model weights, the virtual environment, and the downloaded wheel. Credentials stay on their original machines. Issue-comment publication still requires approval.
