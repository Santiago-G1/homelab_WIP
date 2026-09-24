> [!WARNING]  
> **Work in Progress:** This repository is currently under active development.

# Homelab
Infrastructure automation repository for shifting from manual Proxmox GUI management to a fully automated, declarative GitOps workflow. This project leverages Terraform for provisioning, Ansible for configuration management, and Docker Compose for application deployment.

## Project Goal

The primary objective of this repository is to Automate my homelab in case i make a mess and destroy everything. This includes:
- Declarative Infrastructure as Code (IaC)
- Automated node and container configuration
- Containerized service orchestration
## Architecture

![Architecture Diagram](/docs/homelab-visual.drawio.svg#gh-light-mode-only)
![Architecture Diagram](/docs/homelab-visual.drawio.svg#gh-dark-mode-only)

## Hardware:
- **WAN:** Starlink Standard 4 (Bypass Mode)
- **Routing:** Cudy WR3000 (192.168.10.1)
- **Switching:** Mercury 1Gbps 5-port switch
- **Compute:** Main Proxmox VE Server (pve 9.2.3)
- **Backup:** Dedicated Proxmox Backup Server (192.168.10.9)

The infrastructure is segmented into distinct layers managed via automated pipelines:
- **Provisioning Layer:** Proxmox VE managed via Terraform providers to spin up LXC containers dynamically.
- **Configuration Layer:** Ansible playbooks handling base OS hardening, package installations, and Docker daemon setups.
- **Application Layer:** Isolated Docker Compose deployments grouped logically by service types (e.g., Media/Arr suite, Frontend tools).
---
## Deployed Services
### Management Services
- **Devops (192.168.10.11):** IaC repository, Terraform + Ansible control node

### Network Services
- **Adguard (192.168.10.3):** Adguard Home (Port 81)
- **Nginx Proxy Manager (192.168.10.4):** NPM (Port 81)
- **Tailscale (192.168.10.5):** Tailscale mesh VPN node
- **Cloudflare (192.168.10.6):** Cloudflare Tunnel (Handles external exposure for internal services like Navidrome)

### Monitoring Services
- **Monitor (192.168.10.10):** Prometheus (9090), Grafana (8080)

### Media Services
- **Arrsuite (192.168.10.20):** qBittorrent (8080), Radarr (7878), Sonarr (8989), Prowlarr (9696), Bazarr (6767), Seerr (5055), Flaresolverr (8191), Slskd (5030), Calibre (8082)
- **Frontend (192.168.10.21):** Navidrome (4533), Jellyfin (8096), Komga (25600)
- **Immich (192.168.10.22):** Immich (2283)

### Productivity Services
- **Vaultwarden (192.168.10.23):** Vaultwarden (8000)
- **Radicale (192.168.10.24):** Radicale (5232)
- **Quantum Filebrowser (192.168.10.25):** Quantum Filebrowser (8080), Syncthing (8384)
- **AI-Stack (192.168.10.26)** Llama-Swap (5001), Litellm (4000), Open-webui (3000), Comfyui (8188)

---

## Technical Pipeline (Implementation Workflow)

### 1. Infrastructure Provisioning (Terraform)
- **Network Services:** Core DNS, reverse proxies, and networking routing.
- **Media & Arr Suite:** High-throughput storage connections for automated media management.
- **Productivity:** Day to Day tools.
- **Monitoring & Observability:** Isolated instances dedicated to system metrics collection.

### 2. Configuration Management (Ansible)
Once the underlying infrastructure is provisioned, Ansible connects to the newly created hosts to bring them to their desired state without manual intervention. Responsibilities include:
- Establishing secure SSH configurations and user management.
- Installing the Docker runtime engine and dependencies.
- Injecting required environment variables and setting up system mount points.
- Orchestrating the execution of local Docker Compose stacks.
---

