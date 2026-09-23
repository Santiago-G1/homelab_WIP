terraform {
  required_providers {
    proxmox = {
      source  = "Telmate/proxmox"
      version = "~> 2.9"
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
  pm_api_url          = var.proxmox_api_url
  pm_api_token_id     = var.proxmox_api_token_id
  pm_api_token_secret = var.proxmox_api_token_secret
  pm_tls_insecure     = true
}
