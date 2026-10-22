# Dashboard (Glance)

`https://home.<domain>` (internal), served by Caddy from **CT 110** next to
Prometheus and Grafana.

```sh
ansible-playbook playbooks/site.yml --limit monitoring   # deploy / update Glance
ansible-playbook playbooks/site.yml --limit monitoring:proxy   # dashboard + route
ansible-playbook playbooks/verify.yml                    # availability + route checks
```

## One place declares a service

`ansible/inventories/group_vars/all/services.yml` is the single source of truth
for everything published through Caddy. A new service is one entry:

```yaml
  - host: myapp                # becomes myapp.<domain>
    server: myhost             # inventory hostname (hosts.ini); its IP comes from there
    port: "{{ service_ports.myapp }}"   # add myapp to the service_ports map
    title: My app
    icon: di:myapp             # di: dashboard-icons, sh: selfh.st, si:, mdi:
    group: Apps                # bookmark / monitor section
    path: /health              # availability probe (default /)
    verify: true               # check the route in playbooks/verify.yml
    release: owner/myapp       # GitHub repo for the "updates" widget
```

From that entry Ansible renders:

| Rendered from the catalog | File |
| --- | --- |
| `map {host} {backend}` route table | `roles/stacks/templates/caddy-Caddyfile.j2` → `/opt/docker/caddy/Caddyfile` |
| Availability list, bookmarks, updates widget | `roles/stacks/templates/glance.yml.j2` → `/opt/docker/glance/config/glance.yml` |
| Route checks | `proxy_checks` in `host_vars/caddy.yml`, consumed by `playbooks/verify.yml` |

Addresses that are not routes come from the inventory instead of the file
(Prometheus and the GPU panel are built from `hostvars[...].ansible_host`), so
no LAN address is hard-coded in the dashboard template.

## The GPU control panel

It is part of the dashboard, not a separate destination:

* a **metric card** (`GPU & LLM`) that reads the panel's own
  `GET /api/status` with the vault's `vault_gpu_panel_token` as `x-api-token`,
  showing temperature, utilisation, power, VRAM, how many models llama.cpp has
  resident, Immich ML and Jellyfin's accelerator. When the panel reports an
  error (for example the P100 off the bus) the card prints the panel's message
  instead of breaking;
* an **iframe** on the `AI` page with the full panel, so the mode buttons,
  power limit and llama/Immich actions are reachable from the same page.

Both point at the plain API/UI the panel already exposes, so nothing in
`app.py` had to change and no second dashboard runs anywhere: the panel's UI is
simply embedded.

## Widgets

| Widget | Source |
| --- | --- |
| Availability | one site per catalog entry, probed through Caddy (`check-url`) |
| Homelab (hosts up / CPU / RAM / disk) | Prometheus, `count(up == 1)` + `node_*` metrics |
| DNS (queries / blocked / cache) | Prometheus, `blocky_*` metrics (the `dns-stats` widget only speaks AdGuard/Pi-hole/Technitium) |
| GPU & LLM | the GPU control panel API (see above) |
| Updates | GitHub releases of every catalog entry with a `release:` |
| Applications | bookmarks, grouped by the catalog's `group` |
| llama.cpp | `GET /v1/models` on the AI container (router mode: per-model status) |
| LocalLLaMA / LocalLLM | Reddit — see the note below |
| Clock / search | head widgets; the search box has `!yt`, `!gh` and `!lab` bangs |

### If Reddit returns 403

Reddit blocks unauthenticated API access from datacenter/VPS addresses. From a
residential connection the widget works as is; otherwise register an app at
<https://ssl.reddit.com/prefs/apps/> and add it to both reddit widgets:

```yaml
                app-auth:
                  name: ${REDDIT_APP_NAME}
                  id: ${REDDIT_APP_CLIENT_ID}
                  secret: ${REDDIT_APP_SECRET}
```

The three values then belong in the vault (`vault_reddit_*`) and in the stack's
`env:` block in `host_vars/monitoring.yml`, next to the other secrets.

## Secrets

`glance.yml` contains no secret: it uses Glance's `${...}` environment syntax
and the values arrive from the stack's `.env`, which Ansible renders from the
vault (`vault_glance_secret_key`, `vault_glance_admin_password`,
`vault_gpu_panel_token`) with mode 600. The login is `admin` (see
`glance_admin_user`) plus `vault_glance_admin_password`.

The session key must be base64 that decodes to exactly 64 bytes: Glance refuses
to start otherwise (`secret-key must be exactly 64 bytes`). Generate it with
`docker run --rm glanceapp/glance secret:make` or
`openssl rand -base64 64 | tr -d '\n'` (88 characters).

Two operational notes:

* Glance substitutes environment variables **at startup**, so a change to
  `.env` needs `docker compose up -d` (or a restart) — editing `glance.yml`
  alone is picked up by its config watcher.
* Regenerating `vault_glance_secret_key` invalidates every session cookie
  (`docker run --rm glanceapp/glance secret:make`).
