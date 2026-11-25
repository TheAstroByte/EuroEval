# EuroEval #2310 Step 0: Apple Silicon spike (run on the Mac)

**For the agent running this.** Measure whether EuroEval's existing vLLM backend can do
volunteer-worker evaluations on Apple Silicon through vllm-metal. Then post a short
findings comment on https://github.com/EuroEval/EuroEval/issues/2310. **Change no code
and open no PR.** A second agent on another laptop implements from your comment, so the
comment is the whole handoff. The implementation plan is
`2026-11-24-euroeval-2310-implementation.md`. Read it only for context.

The issue was written by Dan (`saattrupdan`), the main maintainer. Background:

- The worker today only discovers NVIDIA GPUs and always sets `CUDA_VISIBLE_DEVICES`.
  The plan adds a Mac branch, and your measurements decide its constants.
- `vllm-metal` is built on **MLX**, not torch MPS. Memory therefore has to be measured
  from the MLX side and from the OS, not only from `torch.mps`.

Bounds:

- Stop after about 3 hours.
- Use small models only, so total downloads stay under about 30 GB.
- Do not run `uv run euroeval-worker` against the live broker. That claims real queue
  work.

## Setup

Run every block below in **bash**, by starting `bash` first. The macOS default zsh treats
inline `#` comments as commands when you paste them.

```bash
mkdir -p ~/Developer && cd ~/Developer
git clone https://github.com/EuroEval/EuroEval.git && cd EuroEval
git rev-parse --short HEAD
mkdir -p /tmp/ee-step0
sw_vers; uname -m; sysctl -n machdep.cpu.brand_string hw.memsize
xcode-select -p
```

Record the commit (the plan was written against `1fd4035f`) and whether Command Line
Tools exist. All logs go to `/tmp/ee-step0`.

## S1. Install via the existing flow

```bash
time make install 2>&1 | tee /tmp/ee-step0/s1-install.log
```

- `make install` may prompt for `.env` values. Leave them blank, since no tokens are
  needed for public models.
- If a step fails, record the error and the smallest fix that got past it, such as
  installing Xcode CLT, Rust or cmake. Then continue.
- These fixes become the documented macOS prerequisites, so record **only** what was
  actually needed.

Then record the versions:

```bash
uv run python -c "import importlib.metadata as m; [print(p, m.version(p)) for p in ('euroeval','vllm','vllm-metal','mlx','torch','transformers')]" | tee /tmp/ee-step0/s1-versions.txt
uv run python -c "import torch; print('mps', torch.backends.mps.is_available(), torch.mps.recommended_max_memory())" | tee -a /tmp/ee-step0/s1-versions.txt
uv run python -c "import mlx.core as mx; print(mx.metal.device_info())" | tee -a /tmp/ee-step0/s1-versions.txt
```

## Common flags (every measurement run)

These mirror the worker's `Benchmarker` arguments (`src/euroeval_worker/evaluator.py:240`)
and disable the result cache. Without `--force`, a repeated run can return cached scores
without loading the model, which silently invalidates S3 and S4.

```bash
cat > /tmp/ee-step0/ee <<'SH'
#!/bin/bash
exec uv run euroeval --evaluate-val-split --force --no-save-results --raise-errors --requires-safetensors --verbose "$@"
SH
chmod +x /tmp/ee-step0/ee
EE=/tmp/ee-step0/ee
```

Run every `$EE` command from `~/Developer/EuroEval`.

## S2. Every worker task type through the existing vLLM backend

Use the worker's English generative scope from `api/worker/scope-policy.json`, one
dataset per task group:

| Task group | Dataset | Must prove |
|---|---|---|
| sequence_classification | `sst5` | label logprobs + structured labels |
| multiple_choice_classification | `hellaswag` | label logprobs |
| token_classification | `conll-en` | structured output (JSON schema) |
| question_answering | `squad` | free generation |
| text_to_text | `cnn-dailymail` | long generation |
| contamination canary | task `contamination-detection` | canary collected |

Model A is `Qwen/Qwen3-0.6B#no-thinking`. The `#no-thinking` selector is required.
Without it, EuroEval detects Qwen3 as a reasoning model and turns off label logprobs and
structured output (`vllm.py:1052`, `tokenisation_utils.py:299`). The run would then pass
without testing them. If you swap in another model, it must be a non-reasoning instruct
model.

```bash
cd ~/Developer/EuroEval
M=Qwen/Qwen3-0.6B#no-thinking
for d in sst5 hellaswag conll-en squad cnn-dailymail; do
  /usr/bin/time -l $EE --model "$M" --dataset $d --gpu-memory-utilization 0.8 2>&1 | tee /tmp/ee-step0/s2-A-$d.log
done
$EE --model "$M" --task contamination-detection --language en --gpu-memory-utilization 0.8 2>&1 | tee /tmp/ee-step0/s2-A-canary.log
```

For each run, record pass or fail, the score line and the wall time. A pass also needs
this evidence in the verbose log:

```bash
grep -HE "reasoning model|Using logprobs as evaluation strategy|Using structured generation|Not using structured|logprobs" /tmp/ee-step0/s2-A-*.log
grep -H "Contamination canary" /tmp/ee-step0/s2-A-canary.log
```

- **sst5, hellaswag and conll-en:** the log must **not** contain "is a reasoning model".
- **sst5 and hellaswag:** each log must show "Using logprobs as evaluation strategy …"
  (`tokenisation_utils.py:397`). Without that line, the task may have scored through a
  text-label fallback, so record it as a logprobs gap, not a pass. The line alone is not
  enough: any later "fall back to … word edit distance" message in the same log is also
  a logprobs gap (`task_group_utils/sequence_classification.py:333-374`).
- **sst5 and conll-en:** each log must show "Using structured generation …".
- **Canary:** it passes only on `status=collected, count=256`. Any other status or reason
  is a finding, even if the command exits 0.
- **Failures:** record the **exact** exception with file and line, and say whether it is in
  `src/euroeval/` or in vllm/vllm-metal.
- **OOM:** if `0.8` hits the existing Metal OOM hint, retry with `0.5` and then `0.3`, and
  record the highest value that works.

## S3. Memory: cap source, utilisation meaning, headroom

The plan reports usable memory with the existing GB10 formula:

```text
usable = min(cap, max(0, host_available - headroom))      # headroom today = 1 GiB
gpu_memory_utilization passed to vLLM = 0.8 * usable / total   # runtime.py:659
```

`cap` is a recommended working-set **limit**, not current free memory. The candidates are
`torch.mps.recommended_max_memory()` and MLX's `max_recommended_working_set_size`.
`host_available` is current available host memory. S3 produces each input and checks the
result.

1. **Static inputs.** Record total RAM (`hw.memsize`), both cap candidates, and the page
   size from the `vm_stat` header.
2. **The meaning of `gpu_memory_utilization` in vllm-metal.** Search the installed source
   (`grep -rn gpu_memory_utilization .venv/lib/python3.12/site-packages/vllm_metal`) and
   record what it is a fraction of, and what it pre-allocates (KV cache only, or the full
   budget). Cite file:line.
3. **Sampler.** Start it in a second terminal and keep it running through S3 and S4:

   ```bash
   while true; do
     echo "=== $(date +%T)"; vm_stat; sysctl vm.swapusage
     sysctl -n kern.memorystatus_vm_pressure_level
     ps -Ao pid,ppid,rss,command | grep -E "[e]uroeval|[v]llm|[E]ngineCore"
     sleep 2
   done > /tmp/ee-step0/s3-mem.log 2>&1
   ```

   The pressure level reads 1 for normal, 2 for warn and 4 for critical. Estimate
   `host_available` from each snapshot as `(Pages free + Pages inactive) * page_size`.
   "Pages free" already includes the speculative pages, so do not add them again. This is
   an availability estimate, not an exact Darwin equivalent of Linux `MemAvailable`. Sum the RSS of the euroeval and engine
   processes and label the result **aggregate RSS**. RSS is not the physical footprint.
   For each sweep run, also capture the real footprint of those processes near peak with
   `footprint -p <pid>` (`sudo` may be needed), and record it in MiB. Report any gap
   between the two figures. Do not assume Metal buffers are included in RSS.
4. **Utilisation sweep.** Run `$EE --model "$M" --dataset sst5` once each at
   `--gpu-memory-utilization 0.3`, `0.5` and `0.8`. Each one is a fresh run because of
   `--force`. For each, record:
   - the KV-cache or allocation size vllm-metal logs at startup;
   - the peak aggregate RSS and the `footprint` total;
   - the minimum `host_available`;
   - the peak pressure level;
   - the swap delta.

   This checks the source reading from step 2 against observed allocations.
5. **Planned value.** Take an idle snapshot, compute the formula with headroom 1 GiB and
   both cap candidates, then run sst5 at the resulting utilisation. Record whether it
   succeeded, its peak pressure and its swap.
6. **Decision.**
   - Recommend **one** cap source, and the headroom.
   - The headroom is enough if the planned value ran at normal or warn pressure without
     swap growth. Otherwise give the smallest value that would have prevented it.
   - Say whether `runtime.py:659`'s scaling is right for vllm-metal's meaning of the
     fraction.

## S4. Two models in sequence, cleanup, interrupt

Model B is `HuggingFaceTB/SmolLM2-360M-Instruct`, a different architecture. Set `U` to
the utilisation that S3 step 5 verified, and pass it to both commands. The CLI default of
0.8 might fail before these tests reach what they measure.

```bash
U=<verified value from S3 step 5>
```

1. With the sampler running:

   ```bash
   $EE --model "$M" --model HuggingFaceTB/SmolLM2-360M-Instruct --dataset sst5 --gpu-memory-utilization $U 2>&1 | tee /tmp/ee-step0/s4-two-models.log
   ```

   Confirm in the log that **both** models loaded and produced scores. Use the sampler's
   aggregate RSS for the timeline. Also run `footprint -p <pid>` three times, recording
   MiB: during model A, in the gap after model A's scores print and before model B
   loads, and during model B. If you miss the gap, report it as unobserved rather than
   using RSS in its place.
2. **Interrupt.**
   - Start `$EE --model "$M" --dataset cnn-dailymail --gpu-memory-utilization $U`.
   - Wait until the log shows generation has started.
   - Press Ctrl-C once.
   - Then run the check below. Record whether any child process survived, and whether it
     stopped on its own within 30 s.

   ```bash
   sleep 5; pgrep -fl "vllm|EngineCore|euroeval" || echo "no leftover processes"
   ```

## S5. Unsupported model and the registry check

The worker's preflight trusts `ModelRegistry.get_supported_archs()`
(`src/euroeval_worker/safety.py:353`). The plan sends this list to the broker to filter
work. Check whether it is true on Metal:

```bash
uv run python -c "from vllm.model_executor.models.registry import ModelRegistry as R; a=sorted(R.get_supported_archs()); print(len(a)); print('\n'.join(a))" > /tmp/ee-step0/s5-archs.txt
```

- Pick one generative architecture that **is** in the list but that vllm-metal is
  unlikely to support, such as a MoE, Mamba/hybrid or a quantized checkpoint (AWQ/GPTQ).
  Check vllm-metal's README for its supported list, and keep the model small.
- Run it with `$EE --model <id> --dataset sst5 --gpu-memory-utilization $U`. Record
  whether it fails, how fast, and with what error.
- Classify the result:
  - **Registry gap:** the error shows the backend does not support the architecture or
    quantisation. The plan's decline fallback covers this.
  - **Inconclusive:** a memory, download or install failure, or anything else. Record it
    separately; it is not a registry gap.

## S6. Version compatibility with the live broker

```bash
curl -s "https://euroeval.com/api/worker/release-info?architecture=arm64" | tee /tmp/ee-step0/s6-release.json
uv run python -c "import importlib.metadata as m; print(m.version('euroeval'))"
```

Upload validation strips a trailing `.dev\d*` and then compares the result as a string
(`api/worker/_lib/eee.ts:24`). Record whether the installed version matches the broker's
`euroeval_version` under that rule.

## Report: post to the issue

Write the comment to `/tmp/ee-step0/comment.md`, using the template below and filling in
every bracket. Keep it under about 75 lines and include only facts you observed. Then
show the comment to the operator. **Post it only after the operator approves**:

```bash
gh issue comment 2310 --repo EuroEval/EuroEval --body-file /tmp/ee-step0/comment.md
```

If `gh` is not authenticated, give the operator the file to paste.

```markdown
## Step 0 findings: vllm-metal on Apple Silicon

**Machine:** [chip], [RAM] GB, macOS [ver]. EuroEval @ [sha]: euroeval [v], vllm [v],
vllm-metal [v], mlx [v], torch [v].

**Install (`make install`):** [worked as-is / needed: …]. Verified prerequisites: [list].

**Task coverage (existing vLLM backend, `Qwen/Qwen3-0.6B#no-thinking`):**

| Task group | Dataset | Result | Logprobs / structured output observed | Time |
|---|---|---|---|---|
| sequence_classification | sst5 | [✅ score / ❌ error] | [yes/no; fallback seen?] | |
| multiple_choice_classification | hellaswag | | [logprobs yes/no; fallback seen?] | |
| token_classification | conll-en | | [structured yes/no] | |
| question_answering | squad | | n/a | |
| text_to_text | cnn-dailymail | | n/a | |
| contamination canary | — | [status=…, count=…] | n/a | |

Highest working `--gpu-memory-utilization`: [x].

**Memory (inputs for the Mac hardware branch):**
- **Inputs:** total [T] GiB; page size [n] B; caps (working-set limits, not free memory):
  torch.mps [a] GiB, MLX [b] GiB; idle host_available [h] GiB.
- **Meaning of `gpu_memory_utilization` in vllm-metal:** a fraction of [...] that
  pre-allocates [...] ([file:line]).
- **Sweep:**

  | util | allocation logged | peak aggregate RSS | peak `footprint` | min host_available (est.) | pressure | swap Δ |
  |---|---|---|---|---|---|---|
  | 0.3 | | | | | | |
  | 0.5 | | | | | | |
  | 0.8 | | | | | | |

- **Planned formula** (headroom 1 GiB, cap = [chosen]): usable [u] GiB → util [r] →
  [ok/failed], pressure [..], swap Δ [..].
- **Recommendation:**
  - cap source: [torch.mps / MLX], because [...];
  - headroom: [1 GiB / N GiB];
  - `runtime.py:659` scaling: [correct / needs …].

**Two models in sequence** (util [U]): both loaded and scored [yes/no]; `footprint` [A] → [gap or "unobserved"] → [B] MiB.
**Ctrl-C:** [no leftover processes / leftover: …].

**Registry vs Metal:** [model] ([arch]) is in the registry and [ran / registry gap: … / inconclusive: …].

**Version:** installed [v] vs broker [v] → [compatible / mismatch].

**Gaps for implementation:** [none / numbered list, each with the error, file:line and
whether it is in `src/euroeval/` or upstream].
```

Last, tell the operator the comment URL, or tell them it is ready to paste.
