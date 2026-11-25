# 72bd08c5: install vllm-metal from its release wheel

**Branch:** `feat/2310-apple-gpu-worker`, commit `72bd08c5` (on top of `cc594abe`).
**Answers:** Gate A A1 failure at `cc594abe`, `mac-results/gate-a-cc594abe/`.

## Change

At `cc594abe`, vllm-metal was installed from its Git tag. That install lacks the prebuilt
Metal extension `vllm_metal/metal/_paged_ops.cpython-312-darwin.so`, so KV-cache start-up
failed (`vllm_metal/metal/__init__.py:232`). `72bd08c5` makes two changes in
`pyproject.toml`:

1. **Wheel source.** It pins the v0.30.0 GitHub release wheel,
   `vllm_metal-0.30.0-cp312-cp312-macosx_15_0_arm64.whl`, instead of the Git tag. The
   wheel ships the `.so` and has the same dependencies as the Git tag. Its sha256 is
   `3955de8b2c75b633ef889b70fa469a4db661a0c5bb2f78e36272d68b16da9353`, which matches
   `uv.lock`.
2. **Python gate.** The wheel is cp312-only, and vllm-metal declares
   `Requires-Python <3.14`. So the Darwin vllm-metal requirement and source are now gated
   on `python_version == '3.12'`, which is what `make install` uses. This follows the
   existing `kev` gate in `pyproject.toml`.

vLLM stays the v0.30.0 Git source. On macOS with Python 3.13 or newer, vllm-metal is no longer installed, so vLLM would use its CPU backend there. That route is unsupported, because `make install` uses 3.12.

`VLLM_METAL_BUILD_FROM_SOURCE=1` was not used, because every contributor would have to
set it.

## Verified on the implementation machine (Linux arm64)

- `uv lock` exits 0 and `uv lock --check` passes. The only changed lock entry is
  vllm-metal, Git to wheel URL.
- `uv sync --frozen` on Linux installs vllm 0.27.1, Transformers 5.14.1 and torch 2.13.0,
  all unchanged.
- The wheel was downloaded and inspected: the `.so` is present, and its `METADATA`
  dependencies match the lock.
- pre-commit passes on the changed files.

Not verified here: the macOS install and run.

## Requested Mac run

Run **Gate A again from Setup**, with a fresh clone at `72bd08c5`, a fresh `u`, and a new
result directory `mac-results/gate-a-72bd08c5/`. Use the current brief plus
`briefs/2026-11-25-mac-run-updates.md`.

1. **Setup: check the extension.** After `make install`, run this. The expected output
   is `True`:

   ```bash
   uv run python -c "import vllm_metal, pathlib; print((pathlib.Path(vllm_metal.__file__).parent / 'metal' / '_paged_ops.cpython-312-darwin.so').exists())"
   ```

   Also confirm that vllm-metal installed from the wheel URL and not from Git:
   `uv pip show vllm-metal` should report 0.30.0, and
   `.venv/lib/python3.12/site-packages/vllm_metal-0.30.0.dist-info/direct_url.json`
   should contain the wheel URL.
2. **Run A1 to A4** exactly as the brief describes. A1 still requires the
   `--gpu-memory-utilization=<u>` and `metal_limit` log lines. At `cc594abe` the run
   failed before `metal_limit` was logged.
3. **Report** with the brief's template, including the v0.30.0 paragraph from the updates
   file. Add one line saying the install source is now the v0.30.0 release wheel, and
   why.

Part B stays unauthorised until Gate A passes.
