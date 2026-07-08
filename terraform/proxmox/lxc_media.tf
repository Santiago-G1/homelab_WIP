module "arrsuite" {
  source = "../modules/lxc"

  node_name   = var.node_name
  hostname    = "arrsuite"
  vm_id       = 120
  description = "Arr Suite (Radarr, Sonarr, etc.)"
  template    = var.default_template
  os_type     = var.default_os_type
  ip_address  = "192.168.10.20/24"
  gateway     = var.default_gateway
  dns_servers = var.default_dns
  
  disk_size = 8
  cpu_cores = 2
  memory    = 4096
  swap      = 2048
  
  mount_points = [
    {
      mount_path = "/mnt/data"
      volume     = "tank/media"
    }
  ]
}

module "immich" {
  source = "../modules/lxc"

  node_name   = var.node_name
  hostname    = "immich"
  vm_id       = 126
  description = "Immich Photo Management"
  template    = var.default_template
  os_type     = var.default_os_type
  ip_address  = "192.168.10.26/24"
  gateway     = var.default_gateway
  dns_servers = var.default_dns
  
  disk_size = 20
  cpu_cores = 2
  memory    = 6144
  swap      = 2048
  
  mount_points = [
    {
      mount_path = "/mnt/data"
      volume     = "tank/immich"
    }
  ]
}

module "frontend" {
  source = "../modules/lxc"

  node_name   = var.node_name
  hostname    = "frontend"
  vm_id       = 123
  description = "Frontend Dashboard"
  template    = var.default_template
  os_type     = var.default_os_type
  ip_address  = "192.168.10.23/24"
  gateway     = var.default_gateway
  dns_servers = var.default_dns
  
  disk_size = 8
  cpu_cores = 1
  memory    = 2048
  swap      = 2048

  mount_points = [
    {
      mount_path = "/mnt/data"
      volume     = "tank/media"
    }
  ]
}
