variable "node_name" {
  description = "Nombre del nodo Proxmox"
  type        = string
}

variable "hostname" {
  description = "Hostname del contenedor"
  type        = string
}

variable "vm_id" {
  description = "ID del contenedor"
  type        = number
}

variable "description" {
  description = "Descripción del contenedor"
  type        = string
  default     = ""
}

variable "template" {
  description = "Template del sistema operativo"
  type        = string
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
}

variable "dns_servers" {
  description = "Servidores DNS"
  type        = list(string)
  default     = ["1.1.1.1", "8.8.8.8"]
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

variable "unprivileged" {
  description = "Contenedor sin privilegios"
  type        = bool
  default     = true
}

variable "mount_points" {
  description = "Lista de mount points para datasets ZFS existentes"
  type = list(object({
    mount_path = string
    volume     = string
  }))
  default = []
}
