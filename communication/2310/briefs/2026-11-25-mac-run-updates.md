# Updates to the Mac run brief

These operator updates supersede the original brief where they differ.

1. The Darwin pair under test is vLLM v0.30.0 and vllm-metal v0.30.0, introduced at `cc594abe`. An older implementation plan naming v0.34.0 as the candidate is out of date.
2. Include the following paragraph verbatim immediately after the pins line in the Part A issue comment:

**Why v0.30.0 and not newer.** vllm-metal and vLLM are released in matching pairs.
v0.30.0 is the first vllm-metal release that sizes its KV cache from vLLM's
`gpu_memory_utilization` (vllm-metal#756) rather than `VLLM_METAL_MEMORY_FRACTION`,
and it also includes vllm-metal#587 (structured-output bitmask rows) and #667
(requested logprobs). Newer pairs (v0.31+, checked up to v0.34.0) require
`transformers>=5.16.1`. That conflicts with EuroEval's project-wide override
`transformers>=5.14.0,<5.15.0`, which exists because vLLM 0.27.1 on Linux breaks on
Transformers 5.15. Moving beyond v0.30.0 on macOS therefore needs that override
lifted, which means bumping Linux vLLM too. That is out of scope for #2310. The
change is Darwin-only: Linux keeps vllm 0.27.1, Transformers 5.14.1 and torch 2.13.0.

3. The operator must confirm the branch is pushed before Part A starts. The first attempt at `cc594abe` was authorised and is now complete with an A1 failure. A further run records its tested commit and follows the operator's next instruction.
4. The Mac harness separates footprint collection from the two-second guard loop. Each footprint call retains its three-second timeout. This fixes the blocking delay identified in the brief's original harness; the actual harness is in the Gate A evidence archive.

The original Step 0 scripts are historical evidence. Use the current run brief and its updates for further work.
