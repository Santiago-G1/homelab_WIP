terraform {
  required_providers {
    proxmox = {
      source = "Telmate/proxmox"
    }
  }
}

resource "proxmox_lxc" "multiple_mountpoints" {
  target_node     = var.node
  hostname        = var.hostname
  vmid            = var.vm_id
  ostemplate      = var.template
  unprivileged    = var.unprivileged
  ostype          = var.os_type
  cores           = var.cpu_cores
  memory          = var.memory
  swap            = var.swap
  ssh_public_keys = var.ssh_public_keys
  nameserver      = join(" ", var.default_dns)

  features {
    nesting = var.nesting
    keyctl  = var.keyctl
  }

  rootfs {
    storage = var.disk_datastore
    size    = "${var.disk_size}G"
  }

  # Bind mount desde una ruta del host (no un volumen de storage).
  # El provider exige 'size' aunque se ignore en bind mounts.
  dynamic "mountpoint" {
    for_each = var.mount_volume != null && var.mount_volume != "" ? [1] : []
    content {
      key     = "1"
      slot    = 1
      storage = var.mount_volume
      volume  = var.mount_volume
      mp      = var.mount_point
      size    = var.mount_size
    }
  }

  network {
    name   = "eth0"
    bridge = var.bridge
    ip     = "${var.ip_address}/24"
    gw     = var.gateway
  }
}
