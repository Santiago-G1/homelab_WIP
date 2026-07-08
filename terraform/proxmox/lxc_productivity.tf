module "vaultwarden" {
  source = "../modules/lxc"

  node_name   = var.node_name
  hostname    = "vaultwarden"
  vm_id       = 125
  description = "Vaultwarden Password Manager"
  template    = var.default_template
  os_type     = var.default_os_type
  ip_address  = "192.168.10.25/24"
  gateway     = var.default_gateway
  dns_servers = var.default_dns
  
  disk_size = 8
  cpu_cores = 1
  memory    = 2048
  swap      = 2048
}

module "radicale" {
  source = "../modules/lxc"

  node_name   = var.node_name
  hostname    = "radicale"
  vm_id       = 114
  description = "Radicale CalDAV/CardDAV"
  template    = var.default_template
  os_type     = var.default_os_type
  ip_address  = "192.168.10.14/24"
  gateway     = var.default_gateway
  dns_servers = var.default_dns
  
  disk_size = 8
  cpu_cores = 1
  memory    = 2048
  swap      = 2048
}

module "syncthing" {
  source = "../modules/lxc"

  node_name   = var.node_name
  hostname    = "syncthing"
  vm_id       = 115
  description = "Syncthing File Sync"
  template    = var.default_template
  os_type     = var.default_os_type
  ip_address  = "192.168.10.15/24"
  gateway     = var.default_gateway
  dns_servers = var.default_dns
  
  disk_size = 8
  cpu_cores = 1
  memory    = 2048
  swap      = 2048
  
  mount_points = [
    {
      mount_path = "/mnt/data"
      volume     = "tank/obsidian1"
    }
  ]
}


module "filebrowser" {
  source = "../modules/lxc"

  node_name   = var.node_name
  hostname    = "filebrowser"
  vm_id       = 117
  description = "Filebrowser Web File Manager"
  template    = var.default_template
  os_type     = var.default_os_type
  ip_address  = "192.168.10.17/24"
  gateway     = var.default_gateway
  dns_servers = var.default_dns
  
  disk_size = 8
  cpu_cores = 1
  memory    = 2048
  swap      = 2048
  
  
  mount_points = [
    {
      mount_path = "/mnt/data"
      volume     = "tank/cloud"
    }
  ]
}
