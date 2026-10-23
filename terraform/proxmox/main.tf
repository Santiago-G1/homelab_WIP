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

# The address the provider reaches the node on over SSH; it is not always the
# same name the API is published under (NAT, split DNS).
# The node's API certificate is self-signed in a plain homelab, which is what
# insecure = true tolerates. Set it to false once the PVE node has a trusted
# certificate (or the CA is installed on the machine running Terraform).
variable "proxmox_tls_insecure" {
  description = "Skip TLS verification of the Proxmox API certificate"
  type        = bool
  default     = true
}

variable "proxmox_ssh_address" {
  description = "SSH address of the Proxmox node"
  type        = string
  default     = "192.168.10.2"
}

provider "proxmox" {
  endpoint = var.proxmox_api_url
  username = var.proxmox_username
  password = var.proxmox_password
  insecure = var.proxmox_tls_insecure

  ssh {
    agent    = true
    username = "root"
    node {
      name    = "pve"
      address = var.proxmox_ssh_address
    }
  }
}
