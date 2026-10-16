# Ansible

Configuration management for the LXC containers provisioned by `terraform/`.
Docker Compose projects from `docker-compose/` are deployed to `/opt/docker/<stack>`.

## Layout

| Path | Purpose |
| --- | --- |
| `inventories/hosts.ini` | Hosts grouped by role; `docker_hosts` run Compose stacks. |
| `inventories/group_vars/all/main.yml` | Shared settings (timezone, packages, paths). |
| `inventories/group_vars/all/vault.yml` | Vault-encrypted secrets rendered into each stack `.env`. |
| `inventories/host_vars/<host>.yml` | Stacks deployed on that container, with their env and data dirs. |
| `roles/common` | Timezone, base packages, admin SSH keys, sshd hardening. |
| `roles/docker` | Docker Engine from the official Debian repository. |
| `roles/stacks` | Syncs a Compose project, renders `.env`, creates data dirs, brings it up. |
| `roles/node_exporter` | Prometheus node exporter as a systemd service (binary release). |
| `playbooks/bootstrap.yml` | Installs Python on freshly created containers. |
| `playbooks/site.yml` | Base configuration, Docker and every declared stack. |
| `playbooks/llm-models.yml` | Local llama.cpp model changes, without recompiling. |
| `playbooks/verify.yml` | End-to-end check: running containers and HTTP endpoints. |

## Prerequisites

1. **SSH access.** `terraform/modules/lxc` authorizes the control node's own
   public key on every container it creates (`admin_public_key_path`, by default
   `/root/.ssh/id_ed25519.pub` on the machine running Terraform), so a fresh
   container is reachable by Ansible without any manual step. The provider marks
   `initialization.user_account.keys` as ForceNew, so the module seeds it only at
   creation time and ignores later changes; on running containers the key list is
   managed by `admin_authorized_keys` in `group_vars/all/main.yml`.

   Containers created before that key existed (or by a machine that has no such
   key) still need the one-off bootstrap from the Proxmox host:

   ```bash
   pct exec <vmid> -- bash -c "mkdir -p /root/.ssh && echo '<devops pubkey>' >> /root/.ssh/authorized_keys"
   ```

2. **Tank permissions.** Bind mounts under `/tank` are shared with the containers
   through POSIX ACLs keyed by the *mapped* uid: an unprivileged container maps
   uid `N` to host uid `100000 + N`. Examples:

   ```bash
   setfacl -m u:101000:rwx -m d:u:101000:rwx /tank/obsidian  # uid 1000 inside
   setfacl -m u:100999:rwx -m d:u:100999:rwx /tank/immich    # uid 999 inside
   ```

3. **Vault password** in `ansible/.vault_pass` (gitignored). Without it the
   secrets in `vault.yml` cannot be decrypted.

4. **rsync on the control node** (the `synchronize` module pushes the Compose
   projects with it).

5. **PVE firewall.** Containers with `firewall=1` (devops) only accept traffic
   from the `admindevices` ipset, so the monitoring container is listed there to
   let Prometheus scrape it:

   ```
   [IPSET admindevices]
   192.168.10.10 # monitoring (Prometheus scrapes the rest)
   ```

## Usage

```bash
cd ansible
ansible-playbook playbooks/bootstrap.yml   # only for fresh containers
ansible-playbook playbooks/site.yml        # base + Docker + stacks
ansible-playbook playbooks/verify.yml      # end-to-end verification
```

Limit a run with `--limit <host>` and preview with `--check --diff`.

## Adding a local model

llama.cpp runs in **router mode**: it loads whichever `.gguf` in
`llamacpp_models_dir` (`/mnt/data/models` on the AI host, `/tank/cloud/llm` on
the PVE host) a request names. Adding a model is therefore data, not code —
there is nothing to compile.

1. Put the `.gguf` in the models directory. From the control node:

   ```bash
   scp my-model.gguf root@192.168.10.26:/mnt/data/models/
   ```

2. Advertise it in `inventories/host_vars/llm.yml` under `litellm_models`. The
   name is the **file name without `.gguf`**, exactly as the router prints it
   (`curl http://192.168.10.26:8080/v1/models`):

   ```yaml
   litellm_models:
     - my-model
   ```

3. Optional: size it for the P100 in `llamacpp_model_overrides`, keyed by the
   same name. Without an entry it inherits `llamacpp_global_args` (8K context),
   which almost always fits; the VRAM-hungry presets are the 64K + `draft-mtp`
   ones. Only the top level of the models directory is addressable — a `.gguf`
   in a subdirectory is published as a directory entry, not a model.

4. Deploy **without rebuilding llama.cpp**:

   ```bash
   ansible-playbook playbooks/llm-models.yml
   ```

   This re-renders the router preset, restarts `llama-server` only if it
   changed, re-deploys the LiteLLM and ZeroClaw stacks (the agent config embeds
   the model name too) and reconciles the agent's virtual-key access. A full
   `site.yml --limit llm` is only needed for a new llama.cpp/CUDA version or
   changed build flags — and it re-fetches `llamacpp_version` (`master` by
   default), so it can trigger a long compile.

5. To point the agent at it, set `zeroclaw_model` (and `zeroclaw_litellm_models`)
   in `host_vars/llm.yml` to that name and run the same playbook. LiteLLM keeps a
   virtual key's allowlist in its database, but the `stacks` role reassigns it
   from the repo on every deploy, so no dashboard surgery is needed.

### The P100 is shared

The card is 16 GB and llama.cpp is not the only tenant: Immich ML (CUDA, ~6.8 GB
when loaded) takes the whole GPU, and Jellyfin can use NVENC. The `gpu-panel` on
the control node arbitrates. A model whose **weights alone exceed the VRAM left
free** fails to load with `cudaMalloc failed: out of memory`; on a cold start
with Immich ML running, switching the panel to `llm` mode first (which stops
Immich ML) avoids the race. `--models-max 1` means only one model is resident at
any time.

## Secrets

Secrets live encrypted in `inventories/group_vars/all/vault.yml` and are rendered
into each stack `.env` at deploy time, so no plaintext secret is committed:

```bash
ansible-vault edit inventories/group_vars/all/vault.yml
```

## Monitoring

- Every container runs `node_exporter` (role `node_exporter`); the scrape targets
  are derived from the inventory (`node_exporter_targets`).
- `host_vars/monitoring.yml` declares the jobs (node exporter, Blocky DNS metrics
  on `192.168.10.3:4000`, Prometheus itself) and the Prometheus and Grafana
  stacks.
- `prometheus/rules/homelab.yml` holds three alert rules (host down, low disk,
  high memory). Grafana is provisioned with the Prometheus datasource and the
  `Homelab overview` dashboard, both versioned in the repo.

Alerts are evaluated by Prometheus and shown in Prometheus and Grafana; there
is no notification channel configured on purpose.

Certificates are issued by Let's Encrypt through the Cloudflare DNS-01 challenge
(the token lives in the vault as `vault_cloudflare_api_token`), including the
`*.domain.com` wildcard, so there is nothing to install on client devices.

The Grafana admin password is the image default (`admin`/`admin`) until the first
login changes it.
