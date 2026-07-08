> [!WARNING]  
> **Work in Progress:** This repository is currently under active development.

# Homelab
Infrastructure automation repository for shifting from manual Proxmox GUI management to a fully automated, declarative GitOps workflow. This project leverages Terraform for provisioning, Ansible for configuration management, and Docker Compose for application deployment.

## Project Roadmap & TODO

The project is currently under active development. Below is the immediate roadmap before this repository achieves stable release:

- [ ] Complete Proxmox provider definitions in `terraform/proxmox/main.tf`
- [ ] Define the Ansible base setup playbooks and inventory structure
- [ ] Implement dynamic inventory generation to bridge Terraform outputs into Ansible
- [ ] Configure multi-service routing via a reverse proxy (e.g., Traefik or Nginx Proxy Manager)
- [ ] Establish GitHub Actions workflows for automated linting and validations
- [ ] Implement secure secrets injection via HashiCorp Vault or encrypted Ansible Vault
- [ ] Author and test GitHub Actions CD runner self-hosted on the local cluster
      
## Project Goal

The primary objective of this repository is to practice production-grade DevOps and Platform Engineering principles within a home lab environment. This includes:
- Declarative Infrastructure as Code (IaC)
- Automated node and container configuration
- Containerized service orchestration
- Secure secrets management
- CI/CD integration for automated testing and deployments

## Architecture

![Architecture Diagram](/docs/diagram.drawio.svg#gh-light-mode-only)
![Architecture Diagram](/docs/diagram.drawio.svg#gh-dark-mode-only)

The physical network is built for stability and self-hosting, utilizing the following hardware path:
- **WAN:** Starlink Standard 4 (Bypass Mode)
- **Routing:** Cudy WR3000 running OpenWrt (192.168.1.1)
- **Switching:** Mercury 1Gbps 5-port switch
- **Compute:** Main Proxmox VE Server (pve 9.2.3)
- **Backup:** Dedicated Proxmox Backup Server (192.168.10.9)

The infrastructure is segmented into distinct layers managed via automated pipelines:
- **Provisioning Layer:** Proxmox VE managed via Terraform providers to spin up LXC containers dynamically.
- **Configuration Layer:** Ansible playbooks handling base OS hardening, package installations, and Docker daemon setups.
- **Application Layer:** Isolated Docker Compose deployments grouped logically by service types (e.g., Media/Arr suite, Frontend tools).

---

## Deployed Services

The environment is logically separated into the following LXC instances, each running dedicated Docker Compose stacks on the `192.168.10.0/24` subnet:

### Network Services
- **Adguard (192.168.10.3):** Adguard Home (Port 81)
- **Nginx Proxy Manager (192.168.10.4):** NPM (Port 81)
- **Tailscale (192.168.10.5):** Tailscale mesh VPN node
- **Cloudflare (192.168.10.7):** Cloudflare Tunnel (Handles external exposure for internal services like Navidrome)

### Media Services
- **Arrsuite (192.168.10.20):** qBittorrent (8080), Radarr (7878), Sonarr (8989), Prowlarr (9696), Bazarr (6767), Seerr (5055), Flaresolverr (8191), Slskd (5030), Calibre (8082)
- **Frontend (192.168.10.23):** Navidrome (4533), Jellyfin (8096), Komga (25600)
- **Immich (192.168.10.26):** Immich (2283)

### Productivity Services
- **Vaultwarden (192.168.10.25):** Vaultwarden (8000)
- **Radicale (192.168.10.14):** Radicale (5232)
- **Syncthing (192.168.10.15):** Syncthing (8384)
- **Quantum Filebrowser (192.168.10.28):** Quantum Filebrowser (8080)

### Monitoring Services
- **Monitor (192.168.10.10):** Prometheus (9090), Grafana (8080)

---

## Technical Pipeline (Implementation Workflow)

### 1. Infrastructure Provisioning (Terraform)
Terraform is responsible for the stateful creation of the Proxmox LXC containers. By utilizing modular components, containers are systematically separated into dedicated functional zones:
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

### 3. Continuous Integration & Continuous Deployment (CI/CD)
The operational lifecycle is managed via a GitOps pipeline. Every commit to the main branch initiates an automated workflow to ensure infrastructure stability:
- **Linting & Validation:** Pre-flight checks executing `terraform validate`, `tflint`, and `ansible-lint`.
- **Dry-Run / Plan Phase:** Generating `terraform plan` outputs on Pull Requests to inspect infrastructure drift.
- **Deployment / Apply Phase:** Automatically applying infrastructure adjustments and triggers for Ansible configuration rollouts upon merging.

---

