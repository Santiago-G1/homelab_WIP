resource "proxmox_lxc" "multiple_mountpoints" {
  target_node  = var.node
  hostname     = var.hostname
  vmid         = var.vm_id
  ostemplate   = var.template
  unprivileged = true
  ostype       = var.os_type
  cores        = var.cpu_cores
  memory       = var.memory
  swap         = var.swap


  ssh_public_keys = <<-EOT
    ssh-rsa <public_key_1> user@example.com
    ssh-ed25519 <public_key_2> user@example.com
  EOT

  rootfs {
    storage = var.disk_datastore
    size    = "${var.disk_size}G"
  }


  dynamic "mountpoint" {
      for_each = var.mount_volume != null && var.mount_volume != "" ? [1] : []
      content {
        key     = "1"
        slot    = 1
        storage = var.mount_storage
        volume  = var.mount_volume
        mp      = "/mnt/data"
        size    = "256G"
      }
    }

  network {
    name       = "eth0"
    bridge     = "vmbr0"
    ip         = "${var.ip_address}/24"
    gw         = var.gateway
    nameserver = join(" ", var.default_dns)
  }
}
