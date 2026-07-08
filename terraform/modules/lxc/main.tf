resource "proxmox_virtual_environment_container" "this" {
  description    = var.description
  node_name      = var.node_name
  vm_id          = var.vm_id
  unprivileged   = var.unprivileged

  initialization {
    hostname = var.hostname
    dns { servers = var.dns_servers }
    ip_config {
      ipv4 {
        address = var.ip_address
        gateway = var.gateway
      }
    }
  }

  operating_system {
    template_file_id = var.template
    type             = var.os_type
  }

  disk {
    datastore_id = var.disk_datastore
    size         = var.disk_size
  }

  dynamic "mount_point" {
    for_each = var.mount_points
    content {
      volume = mount_point.value.volume
      mp     = mount_point.value.mount_path
    }
  }

  cpu { cores = var.cpu_cores }
  
  memory {
    dedicated = var.memory
    swap      = var.swap
  }

  features {
    nesting = var.nesting
    keyctl  = var.keyctl
  }
}
