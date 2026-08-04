# DeepSeek V4 Flash
Purpose of this repo is to run a quantized version of DeekSeek V4 Flash 0731 using `llama.cpp` in docker.

Serves an OpenAI-compatible API on **port 8000** as a drop-in replacement for the vLLM service.

## Machine
- headless machine running Ubuntu Server
- 96gb system memory - not all of it is available (~91gb total, ~81gb available)
- RTX 5090 with 32gb VRAM - **shared, not exclusive**: `vllm_gemma4-31b-nvfp4-mtp` normally owns
  all of it (`--gpu-memory-utilization 0.982`, `restart: unless-stopped`). One GPU LLM at a time.
  `start.sh` stops vLLM, `stop.sh` restores it.
- docker and nvidia docker tools already installed
- Ryzen 9 9900X (12C/24T), driver 610.43.02 / CUDA 13.3, GPU is Blackwell **sm_120**
- Crucial T705 Gen5 NVMe, ~670gb free

## Architecture
```
deepseek-v4-flash/
├── llama.cpp/          upstream submodule, pinned to a release tag (b10244). Never edited.
├── build.sh            builds upstream's .devops/cuda.Dockerfile (target: server) via build args
├── build-async.sh      start|status [--json]|wait|log|stop — build takes ~10-20min
├── update.sh           move submodule to a newer tag (ff-only, refuses dirty tree) + rebuild
├── download-model.sh   throw-away container pulls the GGUF into ~/models/gguf
├── verify-model.sh     shard count + GGUF magic check
├── start.sh            free GPU → run container → wait healthy → re-point agents
├── stop.sh             stop container → restart vLLM  (`--no-restore` to skip)
└── build.number/history
```

No custom Dockerfile: upstream's `.devops/cuda.Dockerfile` already does what we need, driven by
`--build-arg CUDA_VERSION` / `CUDA_DOCKER_ARCH`. If a patch ever becomes necessary, add
`<file>.patched.<ext>` here plus a thin Dockerfile that `COPY`s it over the submodule — never edit
`llama.cpp/` in place.

Image tags per build: `deepseek-v4-flash:b<N>`, `:<upstream-describe>`, `:latest`.
`build.number` bumps only on success.

## Model
`unsloth/DeepSeek-V4-Flash-0731-GGUF`, quant **UD-IQ3_XXS** (104gb, 4 shards).
284B total / 13B active MoE, 43 layers, 256 routed experts (6 active), 1M ctx max.

**Routed experts are ~97.5% of the weights** (~277B of 284B); the dense part is only ~6.5B. So the
dense layers + KV cache go on the GPU and the experts are split GPU/RAM with `--n-cpu-moe`.

Fit: 81gb RAM + 32gb VRAM = 113gb usable > 104gb.
- GPU: ~8gb dense + ~4gb KV + ~0.6gb overhead → ~19gb of experts
- experts ≈ 96gb / 43 layers ≈ 2.23gb per layer → ~8 expert layers fit on GPU
- `--n-cpu-moe 35` leaves ~78gb of experts in RAM vs ~85gb free. **Headroom is ~7gb — tight.**

Measured 2026-08-03 at `N_CPU_MOE=35`: **24.0 tok/s decode**, **264 tok/s prompt processing** (1806-tok
prompt). For reference a DGX Spark managed 15.5-17.4 tok/s decode / 148 tok/s prompt on a comparable
quant. Expect a slower first request after each start — mmap pages the weights in from NVMe lazily
(the server reports healthy in ~16s, long before the weights are resident).

Tuning `N_CPU_MOE` in `start.sh` (measured 2026-08-03, 400-token decode):
| N_CPU_MOE | VRAM used | decode |
|---|---|---|
| 35 (current) | 25.6gb | 24.1 tok/s |
| 33 | 30.3gb | 22.5-23.7 tok/s |

Pushing more experts onto the GPU did **not** help — decode is bound by CPU memory bandwidth on the
layers that remain, and 33 left only 2.3gb VRAM spare. 35 is the better trade. If the box swaps, fall
back to `UD-IQ2_M` (90.9gb) by changing `QUANT`/`MODEL_FILE` in `download-model.sh` + `start.sh`.

mmap stays enabled (the default) so RAM overflow degrades to NVMe paging instead of OOM. Do not add
`--mlock` or `--no-mmap`.

### Models live in `~/models/gguf`, NOT the HF cache
vLLM bind-mounts `~/.cache/huggingface` and pulls by repo id, but `~/scripts/hf-cache-cleanup.sh`
builds its KEEP set by grepping `MODEL_ID=` out of `~/scripts/vllm.sh` and `rm -rf`s everything else
under `hub/`. A GGUF there would be treated as an orphan and deleted. Keeping it at `~/models/gguf`
(the path `~/scripts/llama.sh` already declares) avoids that, and llama.cpp wants a plain file path
anyway rather than the hub's blobs/snapshots symlink layout.

## Flag choices worth remembering
- **f16 KV cache** (no `--cache-type-k/-v`): upstream reports garbage output with quantized KV on this
  architecture. Deliberate deviation from `~/scripts/llama.sh`'s `q8_0` default.
- `--jinja`: required for V4's chat template / tool calling.
- `--restart no`: vLLM's container is `unless-stopped` and also binds 8000 — two auto-restarting
  containers would race for the port after a reboot.
- `--threads 12`: physical cores only; SMT siblings thrash cache.
- Health start period is generous — loading 104gb takes minutes.
- Upstream (PR #24162, merged 2026-06-29) had post-merge reports of KV corruption at `ubatch >= 32`
  *with expert offloading*. If output is garbage, try `-ub 16` and record the result here.

## Ports
8000 = this service / vLLM (mutually exclusive). 8080 = open-webui, do not use. owui already has
`http://host.docker.internal:8000/v1` registered, so it picks this up with no config change.

## Usage
```
./build-async.sh start && ./build-async.sh wait
./download-model.sh
./start.sh
./stop.sh
```

## CLAUDE.md Guidance
- broad architecture of this repo must be recorded in `CLAUDE.md`
- file must be kept in sync with the repo, apply edits to `CLAUDE.md` alongside changes to the repo
- use terse language

## Work Guidance
- scripts are argument-free and configured by the `# --- configuration ---` constants at the top
  - do NOT use env variables to tune our scripts — edit the constant, so there is nothing to memorize
- skip code comments if the code is self-explanatory
- code comments must be extremely terse
- less code is better code
- create and persist small scripts instead of running medium to long bash commands ad-hoc
  - e.g. create `start.sh`, `stop.sh`, `rebuild.sh`, ...
- do not install anything globally
  - example: if a 1-time dependency is required to download a model from hugging-face, just write a script to create and start a throw-away container to get it done
- prefer additive patches over editing
  - example: instead of cloning a repo and applying changes in place, prefer cloning a repo in a subfolder, and "override" files from the subfolder via Dockerfile instructions at build time
