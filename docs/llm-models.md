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
| `zeroclaw_context_window`, `zeroclaw_max_context_tokens` | `zeroclaw-config.toml.j2` → the agent's budget (the model's own `ctx-size`, and 3/4 of it for the context) |

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

## Where the file lives

`llamacpp_models_dir` (`/mnt/data/models`) is the pool, and the pool reads a
21 GiB GGUF at ~60 MB/s: 5m40s to load, which is exactly the silence before the
first token when the panel unloaded the model (or after a restart). The models
ZeroClaw serves are listed in `llamacpp_fast_models` (`host_vars/llm/main.yml`)
and the `llamacpp` role moves them to `llamacpp_fast_models_dir`
(`/var/lib/llama/models`, on the container's root disk, which is the SSD) and
leaves a symlink in the models directory, so the router keeps seeing the same
file name. Measured: **3m25s** instead of 5m40s; the rest of that time is CUDA
context and tensor setup, not I/O.

Two things to keep in mind:

- The SSD is the `local-lvm` thin pool, and it is small: both 21 GiB models fit,
  but the pool sits at ~85 % afterwards. The role checks the free space first and
  says which model it had to leave on the pool instead of filling it; add it to
  the list when there is room and the next deploy moves it.
- A moved model is no longer inside the pool: it lives on the container's disk,
  so a `pct destroy` loses it. The recovery is downloading it again.

## Switching the agent's model

Set `agent: true` on the wanted entry and run the same playbook. ZeroClaw's
`config.toml` and the model name are both re-rendered.

LiteLLM keeps a virtual key's model allowlist in its **database**, not in
`config.yaml`, so the `stacks` role reassigns it through the admin API on every
deploy (the `agent_keys` entry under the `litellm` stack in
`host_vars/llm/main.yml`). No dashboard surgery is needed.

## Prefill is the wait, and the prefix is what makes it short

The P100 does ~550-900 tokens/s of prompt processing, so a 17k-token prompt is
~27 s of silence before the first token (llama.cpp sends nothing until the
prefill ends). llama.cpp reuses its KV cache only while the prompt matches the
cached one token-for-token: asking the same thing again costs 0.35 s, but as
soon as the prefix diverges the whole prompt is processed again.

Two knobs keep that wait down, both of them in this host's config:

- `cache-reuse: 256` in the 35B presets: after a divergence away from the start,
  llama.cpp shifts the cached KV and reuses the matching chunks instead of
  starting from zero. Without it the same 12k prompt cost 14.5 s on every turn
  the agent rebuilt its history; with it, the tail is reused.
- `zeroclaw_max_tool_result_chars` (8k): each tool result stays in the history
  and is re-prefilled every turn, so a 40k-char web page is ~10k tokens of tax
  on every later request.

The dashboard cancels a turn when its WebSocket drops, which shows in the log as
`request cancelled by user` / `interrupted by user` (and in llama.cpp as
`Failed to read connection`) — not a timeout, so keep the tab in the foreground
while a long prompt is being processed.

The classic failure — ZeroClaw says *"The selected model provider rejected the
request"* — is a name mismatch: a `.gguf` file name passed as a model, or a
virtual key that is not allowed to see the model. Both come from the same
`models.yml` entry now.

## One model for the agent

`zeroclaw` gets exactly one provider profile — the `agent: true` entry — because
of two facts that only bite together:

- llama.cpp runs in router mode with `--models-max 1`: asking for another model
  unloads the resident one and reads ~21 GiB again (~200 s).
- ZeroClaw runs the **post-turn memory consolidation** on the agent's own
  profile, so a second profile swapped the agent's model out after every turn
  and the next message paid the reload plus a full re-prefill.

```yaml
  - name: Cyber-Tiel-Coder-35B-A3B-MTP-UD-Q4_K_XL
    agent: true            # the agent's model; profile `litellm.coder`
    agent_alias: coder
```

Every entry with `agent_alias` becomes `[providers.models.litellm.<alias>]` in
`config.toml`, carrying that model's own `ctx-size` and `temp`; `agent: true`
picks the default, and `zeroclaw_models` derives the LiteLLM virtual key's
allowlist from the same list.

The rest of `llm_models` is still served: the router loads those on demand for
any other client that names them through LiteLLM (port 4000). A second profile
for the chat is `agent_alias: <alias>` on one of them plus its
`ZEROCLAW_providers__models__litellm__<alias>__api_key` override in the stack's
compose, at the cost of the swap above after every turn.

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

`Spark-X2.6-4B-Q4_K_M` (4.45B, 3.3 GiB) is the small tier. Its architecture is
`spark2_5`, which the fork carries in `src/models/spark2-5.cpp`, so it is data
like any other model here. It is hybrid — 36 layers, every fourth attending
fully and the rest sliding at 512 tokens — so only 9 layers grow, at ~35.6
KiB/token of KV in f16.

| KV | ctx | VRAM on the card | decode, short | prefill |
|---|---|---|---|---|
| f16 | 131072 | 8.2 GiB | 80.6 t/s | 1,203 t/s (pp2048) |
| f16 | 262144 | 12.8 GiB | 80.5 t/s | — |
| q8_0 | 524288 | 13.3 GiB | 60.6 t/s | — |

Prefill at 99,382 tokens is 617 t/s on one card and 782 t/s with layer split,
with the needle in the middle retrieved. The preset stays at 131072 in f16 on
**one** card: 8.2 GiB leaves the other for Immich ML, which only binds
`/dev/nvidia0` (`split-mode none` + `main-gpu 1`), and a 6.5 GiB neighbour was
measured next to it without either model noticing. Layer split is the
long-document variant (+27 % prefill, KV 6.4 + 7.5 GiB at ctx 262144) but it
takes both cards.

`flash-attn on` is worth 13 % of the decode, `ub 2048` buys nothing at depth.
Thinking is on by default: `chat_template_kwargs` takes `enable_thinking` and
`reasoning_effort` (`high`/`low`), and the answer arrives in `content` with the
thinking channel in `reasoning_content`.

## Both cards: no P2P, and what it costs

The pair does not support peer access, and the driver says so before any copy:

```
$ nvidia-smi topo -p2p r        # CNS = chipset not supported, both ways
$ ./p2ptest                     # cudaDeviceCanAccessPeer = 0, enablePeerAccess fails
```

One card hangs off the CPU PEG port (`00:01.0`, Gen3 x16) and the other off a
chipset root port (`00:1c.0`, Gen2 x4). The PCH does not forward peer-to-peer
TLPs, and no driver or kernel flag overrides that (IOMMU is not even on), so
`GGML_CUDA_P2P=1` stays as a no-op for the day a card moves to a CPU slot.
Copies stage through host memory instead: 1.37 GiB/s card 0 -> card 1 and 1.51
GiB/s back, while hand-rolled pinned staging is 10-15 % slower — nothing to
patch.

| Spark-X2.6-4B | pp512 | pp2048 | tg128 |
|---|---|---|---|
| one card (Gen3 x16) | 1,160 | 1,206 | 95.7 |
| layer split | 1,157 | **1,533** | 93.4 |
| tensor split | 1,179 | 1,307 | 99.7 |

Layer split pipelines the ubatches, so it *helps* prefill (99k prompt: 782 vs
617 t/s) for 2.4 % of the decode. `tensor` — the stand-in for `row` — loses on
the 35B-A3B (53.4 vs 63.9 t/s), so layer split stays the mode for anything that
has to be split.

`--tensor-split` takes `1/1`, not `1,1`: with a comma `llama-bench` keeps the
whole model on device 0 and the numbers are meaningless. The server accepts
both.
