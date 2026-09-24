terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.78.0"
    }
  }
}
variable "proxmox_api_url" {
  description = "URL PROXMOX API"
  type        = string
}

variable "proxmox_api_token_id" {
  description = "ID token API"
  type        = string
}

variable "proxmox_api_token_secret" {
  description = "API SECRET"
  type        = string
  sensitive   = true
}

provider "proxmox" {
  endpoint  = var.proxmox_api_url
  api_token = "${var.proxmox_api_token_id}=${var.proxmox_api_token_secret}"
  insecure  = true

  ssh {
    agent    = true
    username = "root"
    node {
      name    = "pve"
      address = "192.168.10.2" #change for your pve ip
    }
  }
}

