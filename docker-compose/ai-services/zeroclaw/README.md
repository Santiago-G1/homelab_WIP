# ZeroClaw

Self-hosted agent runtime for the AI container (`192.168.10.26`), deployed as a
Compose stack next to the LiteLLM proxy it talks to. The gateway is served at
`https://agent.<domain>` through Caddy.

```
agent.<domain>  ──►  Caddy (CT 104)  ──►  zeroclaw:42617
                                            │
Telegram (long polling)  ─────────────────► │
                                            ├─ provider: litellm.local
                                            │    http://litellm-proxy:4000/v1
                                            │    (shared `ai-stack` network)
                                            └─ shell tool: throwaway sandbox
                                                 container from
                                                 zeroclaw-sandbox:1
```

Two ways in: the web dashboard behind Caddy (pairing code) and the Telegram
bot (long polling, no inbound port). The agent answers on whichever channel the
message arrived from.

## Layout

| Path | What it is |
| --- | --- |
| `docker-compose.yml` | The stack. Two images are built from it, no secret inside. |
| `image/Dockerfile` | Upstream `v0.8.5-debian` + the Docker CLI the sandbox needs. |
| `sandbox/Dockerfile` | The toolchain every sandboxed command runs in. |

The runtime config is **not** in this directory: Ansible renders
`roles/stacks/templates/zeroclaw-config.toml.j2` into
`/opt/docker/zeroclaw/data/.zeroclaw/config.toml`, next to the daemon's own
state (SQLite memories, pairing tokens).

## Secrets

Two secrets, both in the encrypted vault, both rendered into `.env` by the
`stacks` role; `.env`, `.env.*` and `*.key` are gitignored:

| Vault variable | Reaches the container as |
| --- | --- |
| `vault_zeroclaw_litellm_api_key` | `ZEROCLAW_providers__models__litellm__local__api_key` |
| `vault_zeroclaw_telegram_bot_token` | `ZEROCLAW_channels__telegram__home__bot_token` |

The rendered `config.toml` has neither field: both are schema-mirror overrides
that only ever exist in the process memory (the config carries the alias and
the channel, never the credential). `zeroclaw config save` masks them and never
writes them back, and so does `zeroclaw config list`.

## The sandbox

`sandbox_backend = "docker"` on the `sandboxed` risk profile is what "its own
sandbox" means concretely: ZeroClaw wraps **each** sandboxed shell command in
`docker run --rm --network none --memory 512m --cpus 1.0 zeroclaw-sandbox:1 ...`,
mounting the agent workspace read-only at the same absolute path. Nothing the
agent runs in the shell tool touches the container's own filesystem, has a
network, or can write to the workspace.

Three consequences worth knowing:

1. **The Docker socket is mounted into the ZeroClaw container.** That is how the
   sandbox launches containers, and it is the real trust boundary of this
   deployment: whoever reaches the daemon socket has root on the host. The
   sibling `:debian` image plus the CLI is exactly the cost of this backend.
   The socket-free alternative is `sandbox_backend = "landlock"` (filesystem
   confinement, no container), which needs no socket but is commonly blocked by
   a container's seccomp profile — it was not usable here.
2. **The workspace path must be identical on the host and in the container**
   (`/opt/docker/zeroclaw/workspace`). The sandbox bind-mount is resolved by the
   *host* daemon, so a differing path would silently mount an empty directory.
3. **The sandbox has no network.** Package installs and `git clone` from the
   shell tool fail by design; the toolchain it needs is baked into
   `sandbox/Dockerfile`. ZeroClaw's own HTTP tools (`web_fetch`,
   `http_request`) run in the daemon and are unaffected. Give the sandbox
   network only by editing the backend, not the config: `--network none` is
   hardcoded in the backend.

## Operating

```sh
# Deploy (from the control node, CT 100)
ansible-playbook -i inventories/hosts.ini playbooks/site.yml --limit llm

# Verify
ansible-playbook -i inventories/hosts.ini playbooks/verify.yml --limit llm

# On the AI container
cd /opt/docker/zeroclaw
docker compose ps
docker compose logs -f zeroclaw
docker compose exec zeroclaw zeroclaw config list      # what the daemon loaded
docker compose exec zeroclaw zeroclaw gateway get-paircode --new
docker compose exec zeroclaw docker run --rm zeroclaw-sandbox:1 git --version

# Security posture: the risk profile, the autonomy level and which sandbox
# backend actually came up (expect `active docker`).
docker compose exec zeroclaw zeroclaw security status --agent default
```

### Telegram

The bot (`channels.telegram.home`) is authorized for one identity, the numeric
user ID in `zeroclaw_telegram_user_id` (`host_vars/llm.yml`), through
`peer_groups.telegram_home`. An empty peer set would deny everyone and make the
channel mint a first-user `/bind` code instead, so the ID is pre-authorized on
purpose; add more IDs (or usernames) to `external_peers` to widen it. A
different bot is a new alias, not an edit to this one.

First login needs a paircode: run `get-paircode --new`, then open
`https://agent.<domain>` and paste it.

Upgrading ZeroClaw means bumping the tag in `image/Dockerfile` (both stages),
re-running the playbook (which builds before `up`), and re-checking a chat:
config keys do move between releases.

## Known limits

* The provider model is the `agent: true` entry in
  `host_vars/llm/models.yml`; the `stacks` role reconciles the LiteLLM key's
  scope on every deploy. Change the entry and run
  `ansible-playbook playbooks/llm-models.yml`.
* Public exposure is a Cloudflare tunnel decision, not a Caddy one: the route
  above is internal until `agent.<domain>` is added as a public hostname in the
  tunnel (Zero Trust → Networks → Tunnels).
* `sandbox_backend = "docker"` does not sandbox the non-shell tools
  (`file_read`, `file_write`, …). Those are constrained by
  `workspace_only = true` at the policy layer instead.
