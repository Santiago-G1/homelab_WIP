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

## The 4B fast tier: Spark-X2.6-4B

`Spark-X2.6-4B-Q4_K_M` (XHToken/Spark-X2.6-4B-GGUF, Apache-2.0, 4.45B
parameters, 3.3 GiB) is the small tier: cheap answers, tool calls and long
documents without waking the 35B. It is `spark2_5`, the architecture upstream
llama.cpp learned at `b10828`; the fork carries it in `src/models/spark2-5.cpp`,
so nothing has to be patched for it to load.

It is a hybrid: 36 layers, every fourth with full attention and the rest
sliding at 512 tokens. Only the 9 full layers grow with the context (~35.6 KiB/token in f16); the
sliding ones stay at 512 tokens, which is why a 4B model can hold a six-figure
window on a single card:

| KV | ctx | VRAM on the card | decode, short | decode at depth |
|---|---|---|---|---|
| f16 | 131072 | 8.2 GiB | 80.6 t/s | 50.5 t/s at 99k |
| f16 | 262144 | 12.8 GiB | 80.5 t/s | 61.5 t/s at 52k |
| q8_0 | 262144 | 8.4 GiB | 60.6 t/s | — |
| q8_0 | 524288 | 13.3 GiB | 60.6 t/s | 22.1 t/s at 199k |

Prefill is 1,203 t/s at `pp2048` (llama-bench, ub 1024/2048) and 617 t/s on a
99,382-token prompt, with the needle in the middle retrieved and
`truncated = 0`. `flash-attn on` is worth 13 % of the decode (95.2 vs 84.1 t/s)
and ub 2048 changes nothing at depth (615.6 vs 617.6 t/s) for 286 MiB more.

The preset stays at 131072 in f16 on **one** card, because that is the point
where the tier is still cheap: 8.2 GiB leaves the other card for Immich ML.
`split-mode none` + `main-gpu 1` pins it there (Immich only ever binds
`/dev/nvidia0`), and a 6.5 GiB neighbour on card 0 was measured alongside it
without either model noticing. Splitting the layers across both P100s buys
nothing (94.9 vs 95.7 t/s) — decode is bandwidth-bound, and it would put the
model back on the card Immich uses.

Thinking is part of the model: the chat template takes `enable_thinking`
(default true) and `reasoning_effort` (`high` default, or `low`), both sent as
`chat_template_kwargs` and both rendered by `jinja: "on"`. The answer arrives in
`content` and the thinking channel in `reasoning_content`.

Note the window ladder before promoting it: 262144 in f16 is 12.8 GiB of the
16 GiB card and it did load, but the host hard-reset once right after that load
(the same pattern as the resets under long prefills) — the 131k preset is the
one that has been exercised repeatedly, including 200k-token prompts.

## Both cards, and why P2P is not on the table

The two P100s are not on the same root complex, and the driver says so before
any copy is attempted:

```
$ nvidia-smi topo -p2p r
        GPU0    GPU1
 GPU0   X       CNS
 GPU1   CNS     X            # CNS = chipset not supported

$ ./p2ptest                  # cudaDeviceCanAccessPeer / enablePeerAccess
 p2p 0->1: canAccessPeer=0
 p2p 1->0: canAccessPeer=0
 enablePeerAccess 0->1: peer access is not supported between these two devices
```

The host is an H61 board with an i5-3570: one card hangs off the CPU PEG port
(`00:01.0`, Gen3 x16, `Speed 8GT/s, Width x16`) and the other off a chipset root
port (`00:1c.0`, `Speed 5GT/s, Width x4`). The PCH does not forward peer-to-peer
TLPs between that port and the PEG port, and the driver classifies the pair as
`CNS` regardless of IOMMU state (there is no `intel_iommu=on` on the kernel
command line, so it is not an IOMMU problem either). No driver or kernel flag
overrides `CNS`: `GGML_CUDA_P2P=1` stays set as a harmless no-op, useful only on
the day a card moves to a CPU slot.

What that costs is smaller than it looks. With `split-mode layer` a single
activation crosses the split per token, and a one-card model never touches the
link: Spark-X2.6-4B measured the same 80.6 t/s of decode and 617 t/s of prefill
on the Gen2 x4 card as on the Gen3 one. What it does rule out is tensor-parallel
(`GGML_CUDA_AR_P2P`) and cheap peer copies — `cudaMemcpyPeerAsync` falls back to
1.38 GiB/s here, six times slower than staging through host memory (8.47 GiB/s),
so nothing should be built around cross-device copies.
