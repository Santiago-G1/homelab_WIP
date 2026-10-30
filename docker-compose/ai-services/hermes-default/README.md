# Hermes (default)

The restrained of the two agents on the AI host: `approvals.mode: "smart"` plus a
small `deny` list, no Docker socket, 2 CPU / 3 GB. Unattended runs (`-q`, cron)
deny a dangerous command instead of waiting for an answer.

Its state — memories, sessions, `state.db`, skills — lives on the pool at
`/mnt/data/hermes/default` (host: `/tank/cloud/llm/hermes/default`); the config,
`.env` and `SOUL.md` are rendered by Ansible and bind-mounted over it. Dashboard
at `https://agent.<domain>`, gateway inside the container on 8642.
