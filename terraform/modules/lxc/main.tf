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
  ostype          = "debian"
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

  # Bind mounts desde el host. En el provider, para un bind mount
  # 'storage' y 'volume' deben ser la misma ruta del host, y 'size' es
  # obligatorio aunque Proxmox lo ignore.
  dynamic "mountpoint" {
    for_each = { for idx, mp in var.mount_points : tostring(idx) => mp }
    content {
      key     = mountpoint.key
      slot    = tonumber(mountpoint.key)
      storage = mountpoint.value.volume
      volume  = mountpoint.value.volume
      mp      = mountpoint.value.mount_path
      size    = mountpoint.value.size
    }
  }

  network {
    name   = "eth0"
    bridge = var.bridge
    ip     = "${var.ip_address}/24"
    gw     = var.gateway
  }
}
