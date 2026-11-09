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

## The web UI is not a stack

The dashboard on 9119 is an s6 service **inside** this container, next to the
gateway, so it cannot be "created and left stopped" like ComfyUI: a second
container on the same home answers `gateway_running: false` and stamps
`gateway_state`, which is worse than not having one. What it does have is a
switch:

| `hermes_webui` (host_vars) | what the playbook does |
| --- | --- |
| `true` (default) | `HERMES_DASHBOARD=1` in the container, and the dashboard is started if it was stopped |
| `false` | `HERMES_DASHBOARD=0`: the slot exits before binding, nothing listens on 9119 |

Stop it by hand (the deploy puts it back, that is the point of the switch):

```sh
docker exec hermes /command/s6-svc -d /run/service/dashboard   # off
docker exec hermes /command/s6-svc -u /run/service/dashboard   # on
docker exec hermes /command/s6-svstat /run/service/dashboard   # what it is
```

`s6-svc` and `s6-svstat` live in `/command`, not in `$PATH`. Stopping the
service does not touch the gateway: `platforms` and the models keep running.
