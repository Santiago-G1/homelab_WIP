terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.78.0"
    }
  }
}

# Keys authorized on a container when it is created, so the admin / Ansible
# control node can reach it over SSH immediately. Read from the machine running
# Terraform (the devops container), so no key material lives in the repository.
locals {
  admin_public_keys = (
    var.admin_public_key_path != "" && fileexists(var.admin_public_key_path)
    ? [trimspace(file(var.admin_public_key_path))]
    : []
  )
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

  # Host devices passed through to the container (e.g. NVIDIA GPU, /dev/net/tun).
  # Proxmox writes them as devN: <path> in the container config.
  dynamic "device_passthrough" {
    for_each = var.device_passthrough

    content {
      path       = device_passthrough.value.path
      mode       = device_passthrough.value.mode
      uid        = device_passthrough.value.uid
      gid        = device_passthrough.value.gid
      deny_write = device_passthrough.value.deny_write
    }
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

    # null (the default) means "authorize the admin key"; an explicit list wins.
    user_account {
      keys = var.ssh_public_keys != null ? var.ssh_public_keys : local.admin_public_keys
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
      volume    = mount_point.value.volume
      path      = mount_point.value.mount_path
      read_only = mount_point.value.read_only
    }
  }

  network_interface {
    name   = "eth0"
    bridge = var.bridge
  }

  # The provider marks initialization.user_account.keys as ForceNew, so a change
  # there would recreate the container: the keys are seeded only at creation
  # time (drift on them is ignored on purpose). Use Ansible to change the
  # authorized keys of a running container (roles/common: admin_authorized_keys).
  lifecycle {
    ignore_changes = [initialization[0].user_account[0].keys]
  }
}
