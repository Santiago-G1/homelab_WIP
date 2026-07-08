variable "default_template" {
  description = "LXCs default template"
  type        = string
  default     = "local:vztmpl/debian-13-standard_13.1-2_amd64.tar.zst"
}

variable "default_os_type" {
  description = "Default SO"
  type        = string
  default     = "debian"
}

variable "default_dns" {
  description = "Default dns server (Adguard home, fallback cloudflare)"
  type        = list(string)
  default     = ["192.168.10.3", "1.1.1.1"]
}
variable "default_gateway" {
  description = "default Gateway"
  type        = string
  default     = "192.168.10.1"
}

variable "default_memory" {
  description = "Default ram memory (MB)"
  type        = number
  default     = 2048
}

variable "default_swap" {
  description = "Default LXCs RAM (MB)"
  type        = number
  default     = 2048
}

variable "default_disk_size" {
  description = "Default disk size (GB)"
  type        = number
  default     = 8
}

variable "default_cpu_cores" {
  description = "Default cpu cores"
  type        = number
  default     = 1
}
