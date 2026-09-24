variable "node" {
  description = "Proxmox node name"
  type        = string
  default     = "pve"
}

variable "hostname" {
  description = "Container hostname"
  type        = string
}

variable "vm_id" {
  description = "Container ID"
  type        = number
}

# All containers run Debian.
variable "template" {
  description = "Debian OS template"
  type        = string
  default     = "local:vztmpl/debian-13-standard_13.1-2_amd64.tar.zst"
}

variable "ip_address" {
  description = "IP address without mask (e.g. 192.168.10.20); the module appends /24"
  type        = string
}

variable "gateway" {
  description = "Default gateway"
  type        = string
  default     = "192.168.10.1"
}

variable "bridge" {
  description = "Host network bridge"
  type        = string
  default     = "vmbr0"
}

variable "default_dns" {
  description = "DNS servers (Adguard Home, Cloudflare fallback)"
  type        = list(string)
  default     = ["192.168.10.3", "1.1.1.1"]
}

variable "disk_size" {
  description = "Root disk size in GB"
  type        = number
  default     = 8
}

variable "disk_datastore" {
  description = "Datastore for the root disk"
  type        = string
  default     = "local-lvm"
}

variable "cpu_cores" {
  description = "Number of CPU cores"
  type        = number
  default     = 1
}

variable "memory" {
  description = "RAM in MB"
  type        = number
  default     = 2048
}

variable "swap" {
  description = "Swap in MB"
  type        = number
  default     = 2048
}

variable "unprivileged" {
  description = "Run the container unprivileged"
  type        = bool
  default     = true
}

variable "nesting" {
  description = "Enable nesting (required for Docker)"
  type        = bool
  default     = true
}

variable "keyctl" {
  description = "Enable keyctl (required for Tailscale)"
  type        = bool
  default     = false
}

# NOTE: initialization.user_account.keys is ForceNew in bpg/proxmox: changing
# this list RECREATES the container. The default is empty on purpose (keys are
# injected at creation time); for running containers use Ansible instead.
variable "ssh_public_keys" {
  description = "SSH public keys injected when the container is created"
  type        = list(string)
  default     = []
}

variable "device_passthrough" {
  description = <<-EOT
    Host devices passed through to the container. 'path' is the device on the
    host. For unprivileged containers 'gid'/'mode' may be needed so the
    container user can open the device (e.g. an NVIDIA GPU).
  EOT
  type = list(object({
    path       = string
    mode       = optional(string)
    uid        = optional(number)
    gid        = optional(number)
    deny_write = optional(bool)
  }))
  default = []
}

variable "mount_points" {
  description = <<-EOT
    Bind mounts from the host. 'volume' is the path on the host, 'mount_path'
    is the path inside the container and 'read_only' mounts it read-only.
    Several entries can be declared per container.
  EOT
  type = list(object({
    volume     = string
    mount_path = string
    read_only  = optional(bool, false)
  }))
  default = []
}
