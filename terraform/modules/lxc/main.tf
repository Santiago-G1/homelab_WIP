terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.78.0"
    }
  }
}

resource "proxmox_virtual_environment_container" "multiple_mountpoints" {
  node_name    = var.node
  vm_id        = var.vm_id
  unprivileged = var.unprivileged

  cpu {
    cores = var.cpu_cores
  }

  memory {
    dedicated = var.memory
    swap      = var.swap
  }

  features {
    nesting = var.nesting
    keyctl  = var.keyctl
  }

  disk {
    datastore_id = var.disk_datastore
    size         = var.disk_size
  }

  operating_system {
    template_file_id = var.template
    type             = "debian"
  }

  initialization {
    hostname = var.hostname

    dns {
      servers = var.default_dns
    }

    user_account {
      keys = var.ssh_public_keys
    }

    ip_config {
      ipv4 {
        address = "${var.ip_address}/24"
        gateway = var.gateway
      }
    }
  }

  dynamic "mount_point" {
    for_each = var.mount_points

    content {
      volume = mount_point.value.volume
      path   = mount_point.value.mount_path
    }
  }

  network_interface {
    name   = "eth0"
    bridge = var.bridge
  }
}
