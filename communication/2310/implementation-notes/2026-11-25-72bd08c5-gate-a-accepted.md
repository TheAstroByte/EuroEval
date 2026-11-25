# 72bd08c5: Gate A accepted; changes 1–6 next

**Answers:** `mac-results/gate-a-72bd08c5-a2a4/` (coordination commit `4c548e25`).

## Review of the Mac result

I checked the claims against the raw logs in `evidence.tar.gz`. Its checksum is OK.

- **A2.** SST-5 and HellaSwag each have 20 scored iterations (10 per shot mode). Each has
  zero "fall back … word edit distance" lines, plus the logprobs and
  structured-generation lines, and no reasoning-model detection.
- **A3.** Both CoNLL modes logged the JSON schema. The audits report 252 and 1,608
  unique outputs, with 0 invalid JSON and 0 schema violations.
- **A4.** The canary reports `status=collected, count=256`. The switch log shows both
  models loading and scoring in the same parent, with four benchmarks completed.
- **Every run.** Logged utilisation is 0.60, and each KV budget fits cap × u under the
  amended A1 criterion. Peak pressure is 1, swap growth is 0 MiB, and no owned PIDs
  remain.

**Gate A is accepted.** G1–G3 are closed by the pin bump alone. No `src/euroeval/` change
was needed.

**Teardown diagnostic.** `Segfault encountered` appears at every engine-core shutdown:
once per run, and twice in the switch. The transition capture shows it is in the
`VLLM::EngineCore` child (pid 59622, a child of the EuroEval parent 59445), not the
parent. The parent started a fresh engine for SmolLM2. This is recorded as a known,
non-fatal upstream diagnostic. Nothing is patched. Part B checks it across real worker
leases.

## Next

The operator decided the following:

1. **One PR** to `EuroEval/EuroEval`, containing the worker changes, the broker changes
   and the pin commits `cc594abe` and `72bd08c5`.
2. The implementation machine implements changes 1–6, with a Sol review of each commit,
   and stops **once**, before the Part B push.

**Mac:** nothing to run yet. Part B follows when the operator confirms that the branch is
pushed with changes 1–6.
