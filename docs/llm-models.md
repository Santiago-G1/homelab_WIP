# Local models (llama.cpp + Bifrost + Hermes)

How to add, remove or switch the models served on the AI host (`llm`,
`192.168.10.26`), and how the agent picks one.

## Where models are declared

One file: `ansible/inventories/host_vars/llm/models.yml`.

```yaml
llm_models:
  - name: my-model          # .gguf file name, without the extension
  - name: my-other-model
    agent: true             # the model the agents talk to
    args:                   # per-model llama-server options
      ctx-size: 65536
```

Everything else is derived from that list:

| Derived | Used by |
| --- | --- |
| `llamacpp_model_overrides` | `models.ini.j2` → the router's per-model preset |
| `agent_model` | `hermes-config.yaml.j2` → the model both agents call |
| `agent_models` | the agent's Bifrost virtual key allowlist (`bifrost_virtual_keys`) |
| `agent_extra_models` | models marked `agent_extra: true`, added to the same allowlist |
| `llamacpp_fast_models` | the models marked `fast: true` (kept on the AI host's SSD) |

`name` is the `.gguf` file name **without** its extension: that is what the
router advertises and what clients send. Only the **top level** of
`llamacpp_models_dir` is a model: llama.cpp turns **every subdirectory** into a
model named after the directory (it loads the first `.gguf` inside), so a
directory of spare files shows up in `/v1/models` as a model that cannot be
tuned and confuses every client.

Keep anything that is not a served model outside the directory:

```
/mnt/data/models         served models, one .gguf each (or a symlink)
/mnt/data/models-extra   spare files, drafters   ← storage, never advertised
```

A file that lives in one of those directories and *is* served gets a symlink at
the top of `models`: `Qwen3.8-27B-Uncensored-IQ4_XS.gguf →
/mnt/data/models-extra/uncensored/orcarouter_Qwen3.8-27B-Uncensored-IQ4_XS.gguf`.
The router only ever resolves the name, so it keeps working across a restart.

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
   changed, re-deploys Bifrost and both Hermes stacks, and with them the
   agent key's model allowlist. Models without an `args` entry inherit
   `llamacpp_global_args` (8K context), which almost always fits; the 64K +
   `draft-mtp` presets are the VRAM-hungry ones.

A full `site.yml --limit llm` is only for a new llama.cpp/CUDA version or
changed build flags — it re-checks `llamacpp_version` (and the patch-set tag
that follows it) and can trigger a long compile. See `llamacpp-build.md`.

## Where the file lives

`llamacpp_models_dir` (`/mnt/data/models`) is the pool, and the pool reads a
21 GiB GGUF at ~60 MB/s: 5m40s to load, which is exactly the silence before the
first token when the panel unloaded the model (or after a restart). The models
the agents use are the ones marked `fast: true` in `models.yml`, and the
`llamacpp` role moves them to `llamacpp_fast_models_dir`
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

Set `agent: true` on the wanted entry and run the same playbook. Hermes'
`config.yaml` and the model name are both re-rendered.

`agent_extra: true` is the other flag: that model is added to the agent's
allow-list without becoming the default. It is how a profile reaches its own
`.gguf` while `default` stays on the coding model, and it keeps the name in
`models.yml` instead of hard-coded in `host_vars/llm/main.yml`.

## Which profile gets which model

The two Hermes profiles are split by the kind of model they run, and the split
lives in `models.yml` (never in the rendered config):

| Flag in `models.yml` | Hermes profile | Model |
| --- | --- | --- |
| `agent: true` | `default` | the workhorse |
| `profile: uncensored` | `uncensored` | the abliterated build |

`profile_models` maps the flag to the profile, `hermes-config.yaml.j2` reads it
when it renders each profile's `config.yaml`, and `agent_models` +
`agent_extra_models` form the gateway allow-list that lets both through. A
profile with no model of its own falls back to the `agent: true` one.

The allowlist lives in `bifrost_virtual_keys` (`host_vars/llm/main.yml`), and
`bifrost-config.json.j2` renders it into the gateway's `config.json`, which the
gateway reconciles into its SQLite store on every start. No dashboard surgery is
needed, and a key only ever sees the models it is allowed to use:
`/v1/models` is filtered per key and anything else answers 400 before the
request reaches the router, so an agent cannot make the router load another
model by guessing its name.

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
- Keep tool results small in the prompts you give the agent: every result stays
  in the history and is re-prefilled on later turns, so a 40k-char page is ~10k
  tokens of tax each time.

A cold model still means ~3m25s of silence before the first token, so a turn
that looks stuck is usually the load: watch `/var/log` on the AI host or the GPU
panel before assuming the agent gave up.

The classic failure is a name mismatch: a `.gguf` file name passed as a model,
or a virtual key that is not allowed to see the model. Both come from the same
`models.yml` entry now.

## Two agents, one model

`default` and `uncensored` are two Hermes **profiles**, not two containers: one
runtime, one dashboard, one gateway (Hermes multiplexes profiles by default, so
the process serves both and resolves each turn with that profile's config,
skills, memory and keys). Each profile has its own home under `/mnt/data/hermes`
(`profiles/uncensored` for the second), so its own memories, sessions and
`state.db`, and its own policy:

| | `uncensored` | `default` |
| --- | --- | --- |
| Approvals | `mode: "off"` | `mode: "smart"` + a small `deny` list |
| Unattended (`-q`, cron) | `"approve"` | `"deny"` — it finds another way |
| Policy source | `hermes_agents` in `host_vars/llm/main.yml` | same |

The dashboard is per machine: one server on 9119 with a profile switcher in the
sidebar and `?profile=uncensored` deep links.

They share the model, so nothing evicts anything — the ~200 s reload only happens
when the *model* changes, not when the agent does.
