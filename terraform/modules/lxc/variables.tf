variable "node" {
  description = "Nombre del nodo Proxmox"
  type        = string
  default     = "pve"
}

variable "hostname" {
  description = "Hostname del contenedor"
  type        = string
}

variable "vm_id" {
  description = "ID del contenedor"
  type        = number
}

variable "template" {
  description = "Template del sistema operativo"
  type        = string
  default     = "local:vztmpl/debian-13-standard_13.1-2_amd64.tar.zst"
}

variable "os_type" {
  description = "Tipo de sistema operativo"
  type        = string
  default     = "debian"
}

variable "ip_address" {
  description = "Dirección IP sin máscara (ej: 192.168.10.20); el módulo añade /24"
  type        = string
}

variable "gateway" {
  description = "Gateway por defecto"
  type        = string
  default     = "192.168.10.1"
}

variable "bridge" {
  description = "Bridge de red del host"
  type        = string
  default     = "vmbr0"
}

variable "default_dns" {
  description = "Servidores DNS (Adguard Home, fallback Cloudflare)"
  type        = list(string)
  default     = ["192.168.10.3", "1.1.1.1"]
}

variable "disk_size" {
  description = "Tamaño del disco root en GB"
  type        = number
  default     = 8
}

variable "disk_datastore" {
  description = "Datastore para el disco root"
  type        = string
  default     = "local-lvm"
}

variable "cpu_cores" {
  description = "Número de cores de CPU"
  type        = number
  default     = 1
}

variable "memory" {
  description = "Memoria RAM en MB"
  type        = number
  default     = 2048
}

variable "swap" {
  description = "Swap en MB"
  type        = number
  default     = 2048
}

variable "unprivileged" {
  description = "Contenedor sin privilegios"
  type        = bool
  default     = true
}

variable "nesting" {
  description = "Habilitar nesting (necesario para Docker)"
  type        = bool
  default     = true
}

variable "keyctl" {
  description = "Habilitar keyctl (necesario para Tailscale)"
  type        = bool
  default     = false
}

variable "ssh_public_keys" {
  description = "Claves SSH públicas a inyectar (vacío = ninguna)"
  type        = string
  default     = null
}

variable "mount_volume" {
  description = "Ruta del host a montar por bind mount (ej: /tank/media). null = sin mountpoint"
  type        = string
  default     = null
}

variable "mount_point" {
  description = "Ruta de montaje dentro del contenedor"
  type        = string
  default     = "/mnt/data"
}

variable "mount_size" {
  description = "Requerido por el provider aunque se ignore en bind mounts"
  type        = string
  default     = "256G"
}
