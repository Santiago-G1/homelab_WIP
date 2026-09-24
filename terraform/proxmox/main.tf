terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.78.0"
    }
  }
}

variable "proxmox_api_url" {
  description = "Proxmox API URL"
  type        = string
}

# PVE only lets the root@pam user itself create bind mount points and change
# feature flags (keyctl, fuse): API tokens get an HTTP 403. So authenticate as
# root@pam with its password (kept in terraform.tfvars, gitignored).
variable "proxmox_username" {
  description = "Proxmox user; must be root@pam for bind mounts and feature flags"
  type        = string
  default     = "root@pam"
}

variable "proxmox_password" {
  description = "Password of var.proxmox_username"
  type        = string
  sensitive   = true
}

provider "proxmox" {
  endpoint = var.proxmox_api_url
  username = var.proxmox_username
  password = var.proxmox_password
  insecure = true

  ssh {
    agent    = true
    username = "root"
    node {
      name    = "pve"
      address = "192.168.10.2" # change for your pve ip
    }
  }
}
