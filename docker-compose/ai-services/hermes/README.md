# Hermes

One runtime, two profiles:

| Profile | Policy | Home |
| --- | --- | --- |
| `default` | `smart` approvals + `deny` list; unattended runs deny | `/opt/data` |
| `uncensored` | no approvals; unattended runs approve | `/opt/data/profiles/uncensored` |

State lives on the pool at `${HERMES_DATA}` (`/tank/cloud/llm/hermes`), one
directory per profile. `config.yaml`, `.env`, `SOUL.md` and `workspace/AGENTS.md`
are rendered into it by Ansible; the container mounts the home and the Docker
socket, nothing else.

Both profiles call the same `agent: true` model through LiteLLM, so nothing
evicts the resident GGUF. One dashboard on 9119 serves both: the sidebar switches
profile, and any page takes `?profile=uncensored`.

## Plugins

Installed into the home (they survive a container rebuild, not a re-created home):

```sh
docker exec hermes hermes plugins install holographic
docker exec hermes hermes plugins enable hermes-dreaming
# -u 10000: install.py copies the gates into `scripts/`, cron runs them
# as the hermes user, and root-owned copies are unreadable there.
docker exec -u 10000 hermes python3 /opt/data/plugins/hermes-dreaming/skills/dreaming/scripts/install.py
docker exec -u 10000 hermes python3 /opt/data/plugins/hermes-dreaming/skills/dreaming/scripts/install_cron.py \
    --hermes-home /opt/data --deliver telegram:<chat_id>
```
