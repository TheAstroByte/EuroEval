# Implementation machine notes

Add a dated Markdown note for each pushed change that needs a Mac run. Include:

- the full tested branch SHA;
- the concrete change and local verification;
- the exact Gate A or acceptance checks requested;
- any changed brief or known limitation.

Then update the shared `../STATUS.md` next action.

## Notes

- [2026-11-25 `72bd08c5`: install vllm-metal from its release wheel](2026-11-25-72bd08c5-vllm-metal-wheel.md). This answers the Gate A A1 failure at `cc594abe`.
