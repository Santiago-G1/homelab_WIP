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

### GPU transcoding (Tesla P100)

Jellyfin (`frontend`) and Immich transcode on the Tesla P100 (GP100), and Immich's machine learning runs on it through CUDA. `terraform/proxmox/lxc_media.tf` passes `/dev/nvidia*` into both containers, `roles/nvidia` installs the userspace driver that matches the PVE host, and each Compose project maps the nodes and bind-mounts the driver libraries (an LXC has no `nvidia-container-runtime`).

GP100 has three NVENC engines and NVDEC: **H.264 encode only**, but H.264/HEVC/VP9 decode. HEVC and VP9 sources are decoded in hardware and re-encoded to H.264; HEVC *output* still falls back to software. The Intel iGPU (`/dev/dri/renderD128`) stays passed through as the VAAPI fallback — it is gen 7, so H.264 only, like the P100's encoder.

The P100 is shared with the AI container: the device nodes are passed to `immich` and `frontend` as well, and the nodes belong to gid 991 (Immich) and gid 44 (Jellyfin).

Two settings live inside the applications and cannot be shipped as config, so set them once after a fresh deployment (both persist across container rebuilds):

- Jellyfin: Dashboard → Playback → Transcoding → Hardware acceleration = `NVIDIA NVENC` (stored in `jellyfin/config/encoding.xml`).
- Immich: Administration → Settings → Video transcoding → Hardware acceleration = `NVENC` (stored in the database, so re-select it after restoring one). Machine learning needs no setting: the `-cuda` image uses the GPU when it is present.

Verify with `nvidia-smi` inside the containers and a test encode:

```bash
# inside the Jellyfin container (Immich ships the same ffmpeg build)
/usr/lib/jellyfin-ffmpeg/ffmpeg -init_hw_device cuda \
  -f lavfi -i testsrc=size=1280x720 -frames:v 30 -c:v h264_nvenc -f null -
```

**VRAM is shared with llama.cpp.** The AI container keeps the P100 for `llama-server`; a loaded 27B model takes around 15 GiB of the 16 GiB, so Immich machine learning may not fit while a model is resident. Transcoding needs little VRAM and is not affected. Stop the model (or lower its context) before bulk ML jobs.

### GPU control panel

`https://gpu.domain.com` (basic auth) shows the P100 and decides who uses it.
It runs on the control node and reaches the PVE host over SSH to read
`nvidia-smi` and set the power limit (125-250 W), and the containers to switch
the card between **llama.cpp** and **Immich ML**:

- **LLM**: stops Immich ML, leaving all 16 GiB to llama.cpp.
- **Media**: unloads the llama.cpp models and starts Immich ML.
- **Shared**: both available (only fits with a small llama.cpp model).

Jellyfin and Immich transcoding use little VRAM and only while playing, so they
are not part of the switch. The panel and its stack live in
`docker-compose/app-services/gpu-panel` (role `stacks`, host `devops`).

---
## Deployed Services
### Management Services
- **Devops (192.168.10.11):** IaC repository, Terraform + Ansible control node
- **GPU panel (https://gpu.domain.com):** P100 dashboard and GPU arbitration, served by Caddy (basic auth)

### Network Services
- **Blocky (192.168.10.3):** DNS resolver and ad-blocker, API/DoH/metrics on port 4000
- **Caddy (192.168.10.4):** reverse proxy for `*.domain.com` (ports 80/443, config in `docker-compose/network-services/caddy`)
- **Tailscale (192.168.10.5):** Tailscale mesh VPN node
- **Cloudflare (192.168.10.6):** Cloudflare Tunnel (Handles external exposure for internal services like Navidrome)

### Monitoring Services
- **Monitor (192.168.10.10):** Prometheus (9090), Grafana (3000)

### Media Services
- **Arrsuite (192.168.10.20):** qBittorrent (8080), Radarr (7878), Sonarr (8989), Prowlarr (9696), Bazarr (6767), Seerr (5055), Flaresolverr (8191), Slskd (5030), Calibre (8082)
- **Frontend (192.168.10.21):** Navidrome (4533), Jellyfin (8096), Komga (25600)
- **Immich (192.168.10.22):** Immich (2283)

### Productivity Services
- **Vaultwarden (192.168.10.23):** Vaultwarden (8000)
- **Radicale (192.168.10.24):** Radicale (5232)
- **Quantum Filebrowser (192.168.10.25):** Quantum Filebrowser (8080), Syncthing (8384)
- **AI-Stack (192.168.10.26):** llama.cpp server in router mode (8080), LiteLLM (4000)

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

