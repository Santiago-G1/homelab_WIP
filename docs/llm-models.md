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
changed build flags — it re-checks the pinned `llamacpp_version` (the role
defaults to `master`, the AI host pins a commit) and can trigger a long
compile. See `llamacpp-build.md`.

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
