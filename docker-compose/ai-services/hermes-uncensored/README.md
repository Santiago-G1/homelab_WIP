# Hermes (uncensored)

The one with nothing in the way: `approvals.mode: "off"`, unattended runs
`approve`, the Docker socket mounted, 4 CPU / 6 GB. Everything Docker can reach
is its reach, so treat its dashboard as root on the host.

State on the pool at `/mnt/data/hermes/uncensored`; config, `.env` and `SOUL.md`
rendered by Ansible and bind-mounted over it. Dashboard at
`https://hermes.<domain>`.
