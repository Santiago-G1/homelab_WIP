# Local models (llama.cpp + LiteLLM + ZeroClaw)

How to add, remove or switch the models served on the AI host (`llm`,
`192.168.10.26`), and how the agent picks one.

## Where models are declared

One file: `ansible/inventories/host_vars/llm/models.yml`.

```yaml
llm_models:
  - name: my-model          # .gguf file name, without the extension
  - name: my-other-model
    agent: true             # the model ZeroClaw talks to
    args:                   # per-model llama-server options
      ctx-size: 65536
```

Everything else is derived from that list:

| Derived | Used by |
| --- | --- |
| `litellm_models` | `litellm-config.yaml.j2` → LiteLLM `/v1/models` |
| `llamacpp_model_overrides` | `models.ini.j2` → the router's per-model preset |
| `zeroclaw_model` | `zeroclaw-config.toml.j2` → the agent's provider |

`name` is the `.gguf` file name **without** its extension: that is what the
router advertises and what clients send. Only the top level of
`llamacpp_models_dir` is addressable — a `.gguf` in a subdirectory is published
as a directory entry, not a model.

## Adding a model

llama.cpp runs in **router mode**: it loads whichever `.gguf` a request names,
so a new model is data, not a build.

1. Copy the file to `/mnt/data/models` on the AI host (`/tank/cloud/llm` on the
   PVE host):

   ```sh
   scp my-model.gguf root@192.168.10.26:/mnt/data/models/
   ```

2. Add an entry to `llm_models` in `models.yml` and, only if it needs a
   non-default preset, its `args`.

3. Deploy without recompiling:

   ```sh
   cd ansible
   ansible-playbook playbooks/llm-models.yml
   ```

   This re-renders the router preset, restarts `llama-server` only if it
   changed, re-deploys the LiteLLM and ZeroClaw stacks and reconciles the
   agent's virtual-key access. Models without an `args` entry inherit
   `llamacpp_global_args` (8K context), which almost always fits; the 64K +
   `draft-mtp` presets are the VRAM-hungry ones.

A full `site.yml --limit llm` is only for a new llama.cpp/CUDA version or
changed build flags — it re-checks `llamacpp_version` (and the patch-set tag
that follows it) and can trigger a long compile. See `llamacpp-build.md`.

## Switching the agent's model

Set `agent: true` on the wanted entry and run the same playbook. ZeroClaw's
`config.toml` and the model name are both re-rendered.

LiteLLM keeps a virtual key's model allowlist in its **database**, not in
`config.yaml`, so the `stacks` role reassigns it through the admin API on every
deploy (the `agent_keys` entry under the `litellm` stack in
`host_vars/llm/main.yml`). No dashboard surgery is needed.

The classic failure — ZeroClaw says *"The selected model provider rejected the
request"* — is a name mismatch: a `.gguf` file name passed as a model, or a
virtual key that is not allowed to see the model. Both come from the same
`models.yml` entry now.

## The P100 is shared

The card is 16 GB and llama.cpp is not the only tenant:

- Immich ML (CUDA) uses ~6.8 GB when loaded.
- Jellyfin can use NVENC.
- The `gpu-panel` on the AI host arbitrates.

A model whose weights alone exceed the VRAM left free fails with
`cudaMalloc failed: out of memory` (a 500 from the router). The 27B presets are
~11.2 GB of weights and load at `15551 / 16384 MiB` when the card is free, so
with Immich ML running they cannot load at all — lowering `ctx-size` does not
help.

`gpu-panel` in `auto` mode unloads the LLM after `llama_idle_min` and restarts
Immich ML, which reintroduces the race on the next request. To keep the agent
always available either use `llm` mode (`POST /api/mode/llm`) or set
`llama_idle_min: 0` so the model is never unloaded.

## The fork build that is actually served

`roles/llamacpp` builds the in-tree llama.cpp with the P100 patch set, but the
service is served by the **Kmic-68 fork** (`/opt/llama.cpp-kmic`, branch
`p100-dual-gpu`), which carries the sm_60 kernel work. It is a hand build
(clang + CUDA 12.8, `-DCMAKE_CUDA_ARCHITECTURES=60`, `-DGGML_CUDA_NCCL=OFF`)
because the Pascal tuning is gated on `__CUDA_ARCH_LIST__ == 600`. The role
installs `10-kmic-p100.conf` — the drop-in that points `ExecStart` at that binary
and sets `GGML_CUDA_P2P=1` and `GGML_CUDA_GRAPHS_PRE_VOLTA=3` — only when the
binary exists, so a fresh host still comes up on the in-tree build.

Rebuilds there must pass the CUDA compiler explicitly:

    export PATH=/usr/local/cuda-12.8/bin:$PATH
    cmake -B build-opt -DGGML_CUDA=ON \
      -DCMAKE_CUDA_COMPILER=/usr/local/cuda-12.8/bin/nvcc \
      -DCMAKE_CUDA_ARCHITECTURES=60 -DGGML_CUDA_NCCL=OFF -DCMAKE_BUILD_TYPE=Release
    cmake --build build-opt -j4 --target llama-server

Without `nvcc` on `PATH` CMake reconfigures with `GGML_CUDA=OFF` **silently** and
the server starts on CPU. Check with `llama-bench -ngl 99`: it must print
`ggml_cuda_init: found 2 CUDA devices`.

## The served model: Qwen3.6-35B-A3B with MTP

`Qwen3.6-35B-A3B-MTP-UD-Q4_K_XL` (unsloth MTP GGUF, 21.28 GiB) is the agent
model and the only one declared with `agent: true`. It has the `blk.40` draft
head, so `spec-type: draft-mtp` works; the non-MTP file of the same model has no
draft head and must not be served with MTP.

Measured on the two P100s at 125 W, KV in **f16**:

| | value |
|---|---|
| VRAM | 14.2 GiB (CPU slot) + 14.9 GiB (PCH slot) |
| decode, short context | 56-69 t/s (32.4 t/s without MTP) |
| draft acceptance | 58-69 %, mean draft length 2.7-3.1 |
| prefill | 994 t/s at 91k, 543 t/s for 243,830 tokens from scratch |
| decode at 244k | 21.6 t/s |
| full 262144 window | verified: 243,830-token prompt, `truncated = 0` |

Do not raise `ubatch-size` to 2048 with this model (illegal memory access during
long prefill) and do not add a second slot: `ub 1024` + `parallel 1` is the
stable point, and the spare VRAM is spent on the unquantized f16 KV instead.

Sampling is the Qwen3.6 model card, thinking mode for general tasks:
`temp 1.0, top_p 0.95, top_k 20, min_p 0.0, presence_penalty 1.5,
repetition_penalty 1.0`.
