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
  default     = "debian-13-standard_13.1-2_amd64.tar.zst"
}

variable "os_type" {
  description = "Tipo de sistema operativo"
  type        = string
  default     = "debian"
}

variable "ip_address" {
  description = "Dirección IP con máscara (ej: 192.168.10.3/24)"
  type        = string
}

variable "gateway" {
  description = "Gateway por defecto"
  type        = string
  default     = "192.168.10.1"
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


variable "default_dns" {
  description = "Default dns server (Adguard home, fallback cloudflare)"
  type        = list(string)
  default     = ["192.168.10.3", "1.1.1.1"]
}

variable "mount_storage" {
  description = "Storage para el mountpoint"
  type        = string
  default     = "tank"
}

variable "mount_volume" {
  description = "Volumen o ruta en el host"
  type        = string
  default     = "/tank"
}
