# SearXNG

Metasearch instance on the AI container (`192.168.10.26`), deployed as a Compose
stack on the same `ai-stack` network as LiteLLM and ZeroClaw. It exists because
the agent's `web_search` tool defaults to DuckDuckGo, whose HTML endpoint starts
throttling the daemon after a handful of queries; a local metasearch has no
per-client quota and no API key to rotate.

```
agent tool call ──► zeroclaw ──► http://searxng:8080/search?…&format=json
                                    (ai-stack network)

browser ──► Caddy (CT 104) ──► https://search.<domain> ──► 192.168.10.26:8081
```

Two entry points for one service: the agent resolves the container name on the
shared network, and humans come in through Caddy on the published port. Port
`8080` itself belongs to llama.cpp on this host, which is why the instance is
published on `8081`.

## Layout

| Path | What it is |
| --- | --- |
| `docker-compose.yml` | The stack. Pinned image, cache volume, health check. |
| `config/settings.yml` | Rendered by Ansible from `roles/stacks/templates/searxng-settings.yml.j2`. Not in git: it is a file, not a directory, so the `stacks` role owns it. |
| `data/cache/` | Compiled theme and locales (`/var/cache/searxng`), owned by uid `977` (the image's `searxng` user). |

The settings file only declares the differences from upstream: `use_default_settings`
merges them over the image's full `settings.yml`. That keeps the engine list —
which upstream tunes constantly — out of this repository. The two engines that
need a Tor client (`ahmia`, `torch`) are removed because otherwise every worker
logs a registration error on boot.

## Secrets

One secret, in the encrypted vault, rendered into the stack `.env` (mode 600):

| Vault variable | Reaches the container as |
| --- | --- |
| `vault_searxng_secret_key` | `SEARXNG_SECRET` → `server.secret_key` |

`server.secret_key` signs the session cookie, so it must be random
(`openssl rand -hex 32`); it is never written into the rendered `settings.yml`,
which stays in git.

## Why the limiter is off

`server.limiter: false` and `public_instance: false` are the documented pair for
a private instance. The limiter needs a valkey/redis to keep counts across
workers, and the agent is the only client — a limiter here would just be a way
to 429 our own tool calls. **This is also why the instance must not be published
on the internet**: an open metasearch is a free search proxy for anyone. Caddy
serves it on the LAN; making `search.<domain>` a public hostname in the
Cloudflare tunnel needs a valkey service and the limiter (plus bot detection)
turned on first.

## Operating

```sh
# Deploy (from the control node, CT 100) — no llama.cpp rebuild
ansible-playbook playbooks/llm-models.yml -e '{"stacks_only":["searxng","zeroclaw"]}'

# On the AI container
cd /opt/docker/searxng
docker compose ps
docker compose logs -f searxng

# The agent's own path, JSON included
curl -s 'http://127.0.0.1:8081/search?q=searxng&format=json&pageno=1' | jq '.results[0]'

# Which engines actually registered
docker compose logs searxng | grep -i 'register engine'
```

`playbooks/verify.yml --limit llm` checks `/healthz` (via `health_checks`) and
the Caddy route (via the catalog's `verify: true`).

## Upgrading

The image is pinned to a release tag, not `latest`: SearXNG's settings schema
moves between releases and a silent jump can break the JSON format the agent
depends on. To bump it, change the tag in `docker-compose.yml`, re-run the
playbook, and re-check `/search?format=json` above. `searxng/searxng` tags are
`YYYY.MM.DD-<commit>`; upstream publishes them daily.
