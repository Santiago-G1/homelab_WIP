# GPU control panel — gpu.domain.com

Branch: `feat/gpu-control-panel` (not pushed).

## Summary

A dashboard for the Tesla P100 that shows the card and decides who uses it:

- **Immich fully on the GPU**: machine learning on CUDA (the `-cuda` image) and
  video transcoding on NVENC. The panel reports both.
- **GPU arbitration** between `llama.cpp` and Immich ML with three modes
  (LLM / Media / Shared); Jellyfin and Immich transcoding stay available because
  they use little VRAM and only while playing.
- **Power limit** control (125–250 W) and general card info (temp, usage, VRAM,
  clocks, processes).

Served at `https://gpu.domain.com` (HTTP basic auth).

## What changed

| File | Change |
| --- | --- |
| `docker-compose/app-services/gpu-panel/*` | New FastAPI + static dashboard, container image. |
| `ansible/inventories/host_vars/devops.yml` | Deploys the stack on the control node. |
| `ansible/playbooks/site.yml` | New play: run `stacks` on `management`. |
| `ansible/roles/stacks/tasks/stack.yml` | Optional `build: true` adds `--build` to `docker compose up`. |
| `docker-compose/network-services/caddy/Caddyfile` | Route `gpu.<domain>` → `192.168.10.11:8099`. |
| `ansible/inventories/host_vars/caddy.yml` | Proxy check for the panel. |
| `ansible/inventories/group_vars/all/vault.yml` | `vault_gpu_panel_password`. |

## Why these decisions

- **The panel runs on the control node (devops).** It is the only host with SSH
  reach to the PVE node *and* to every container that uses the GPU, so it can be
  a pure control plane and does not need the GPU itself.
- **It is not added to `docker_hosts`.** The `docker` role installs Docker from
  docker.com, which would fight the Debian Docker package already on devops; the
  new play runs only the `stacks` role there.
- **SSH as the transport.** Reuses the existing admin key instead of inventing a
  new credential, and each probe is a single command.
- **Power limit runs on the PVE host.** Inside an unprivileged LXC `nvidia-smi
  -pl` fails with `Insufficient Permissions`; the panel SSHes to the host for it.
- **Modes instead of per-service switches.** The real conflict is VRAM:
  `llama.cpp` loads ~15 GiB, Immich ML ~3 GiB. So **LLM** stops Immich ML and
  **Media** unloads the llama.cpp models; Jellyfin/Immich transcoding use a few
  hundred MiB on demand and are left alone.
- **Stop the ML container instead of unloading its model.** Immich does not
  expose a model-unload endpoint, so freeing VRAM means stopping
  `immich_machine_learning`; the model auto-unloads after 300 s idle anyway.
- **Base64-delivered shell for the Immich config query.** The `psql`/JSON command
  does not survive nested shells with plain quoting.
- **Basic auth.** The panel can stop containers and change the power limit; the
  password lives in the vault (`vault_gpu_panel_password`), not in the repo.

## Validation

- `GET /api/status` OK both on `127.0.0.1:8099` and through Caddy
  (`https://gpu.domain.com`, HTTP 200).
- Power limit set to `200 W` and restored to `150 W` (`nvidia-smi -pl`).
- Mode `llm` stopped Immich ML (`exited`); mode `balanced` started it
  (`running`, healthy again).
- The dashboard HTML is served with the title `domain.com · GPU Control`.

## Usage

- URL: `https://gpu.domain.com` — user `admin`, password in
  `vault_gpu_panel_password`.
- **LLM** button: frees the card for `llama.cpp` (stops Immich ML).
- **Media** button: unloads llama.cpp models and starts Immich ML.
- **Shared**: both allowed (only fits with a small llama.cpp model).
- Power slider: 125–250 W.

## Caveats

- The panel is LAN-only: `*.domain.com` resolves through Blocky to Caddy; the
  basic auth is the only gate, so it must not be exposed publicly without it.
- Restarting Immich ML briefly interrupts smart search / face jobs (they retry).
- Jellyfin's accel toggle edits `encoding.xml` and restarts Jellyfin.
