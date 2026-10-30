# Hermes

One agent runtime, two profiles:

| Profile | Policy | Where |
| --- | --- | --- |
| `default` | `approvals.mode: "smart"` + a `deny` list; unattended runs deny | root home (`/opt/data`) |
| `uncensored` | `approvals.mode: "off"`; unattended runs approve | `profiles/uncensored` |

Both call the same `agent: true` model through LiteLLM, so nothing evicts the
resident GGUF. Their state — memories, sessions, `state.db`, skills, cron — lives
on the pool at `${HERMES_DATA}` (`/tank/cloud/llm/hermes`), one directory per
profile; `config.yaml`, `.env` and `SOUL.md` are rendered by Ansible and mounted
over it.

One gateway process serves both (Hermes multiplexes profiles by default) and one
dashboard on 9119 manages the whole machine: the sidebar has a profile switcher
and any page takes `?profile=uncensored`.

## Bootstrap the second profile once

Docker mounts a *file* only if the target exists, so the three managed files of a
new profile have to be created before the first deploy:

```sh
install -d -o 10000 -g 10000 -m 700 /mnt/data/hermes/profiles/uncensored
touch /mnt/data/hermes/profiles/uncensored/{config.yaml,.env,SOUL.md}
chown 10000:10000 /mnt/data/hermes/profiles/uncensored/{config.yaml,.env,SOUL.md}
```
