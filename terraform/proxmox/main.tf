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

# Bind mount points and feature flags are root@pam only (API tokens get a 403),
# so authenticate as root@pam with the password from terraform.tfvars.
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

# Over SSH; not always the name the API is published under (NAT, split DNS).
# insecure = true tolerates the node's self-signed certificate.
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
