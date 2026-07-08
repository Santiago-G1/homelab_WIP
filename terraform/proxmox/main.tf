terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.55.0"
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

variable "node_name" {
  description = "PROXMOX NODE NAME" 
  type        = string
}

variable "lxc_password" {
  description = "Default password"
  type        = string
  sensitive   = true
}

provider "proxmox" {
  endpoint  = var.proxmox_api_url
  api_token = "${var.proxmox_api_token_id}=${var.proxmox_api_token_secret}"
  insecure  = true
}
