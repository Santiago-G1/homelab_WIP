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
| `playbooks/verify.yml` | End-to-end check: running containers and HTTP endpoints. |

## Prerequisites

1. **SSH access.** Terraform cannot manage the container SSH keys
   (`initialization.user_account.keys` is ForceNew, so changing it would recreate
   running containers). After creating or recreating a container, bootstrap the
   control node key once from the Proxmox host:

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

The Grafana admin password is the image default (`admin`/`admin`) until the first
login changes it.
