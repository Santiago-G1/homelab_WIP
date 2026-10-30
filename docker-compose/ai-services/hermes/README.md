# Hermes

One agent runtime, two profiles:

| Profile | Policy | Where |
| --- | --- | --- |
| `default` | `approvals.mode: "smart"` + a `deny` list; unattended runs deny | root home (`/opt/data`) |
| `uncensored` | `approvals.mode: "off"`; unattended runs approve | `profiles/uncensored` |

Both call the same `agent: true` model through LiteLLM, so nothing evicts the
resident GGUF. Their state — memories, sessions, `state.db`, skills, cron — lives
on the pool at `${HERMES_DATA}` (`/tank/cloud/llm/hermes`), one directory per
profile; `config.yaml`, `.env`, `SOUL.md` and `workspace/AGENTS.md` are rendered
by Ansible straight into it (absolute `dest` in the stack's `files`), never
bind-mounted: Hermes publishes config by renaming a temp file into place and a
mount point gives EBUSY.

One gateway process serves both (Hermes multiplexes profiles by default) and one
dashboard on 9119 manages the whole machine: the sidebar has a profile switcher
and any page takes `?profile=uncensored`.

## Directories

`dirs` in the stack entry creates `/mnt/data/hermes/workspace` and
`/mnt/data/hermes/profiles/uncensored` as uid 10000 before the files are
rendered there. Nothing else has to exist first.

## Plugins

Installed into `/opt/data/plugins` on the pool (they survive a container
rebuild, but not a re-created home):

```sh
docker exec hermes hermes plugins install holographic   # memory.provider
docker exec hermes hermes plugins enable hermes-dreaming
```

`hermes-dreaming` ships its own cron jobs; install them with its script:

```sh
docker exec hermes /opt/data/plugins/hermes-dreaming/skills/dreaming/scripts/install_cron.py \
    --deliver telegram:<chat_id> --dry-run
```
