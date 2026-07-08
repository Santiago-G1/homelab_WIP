# ============================================
# SERVICIOS DE RED
# ============================================

module "adguard" {
  source = "../modules/lxc"

  node_name   = var.node_name
  hostname    = "adguard"
  vm_id       = 103
  description = "Adguard Home DNS"
  template    = var.default_template
  os_type     = var.default_os_type
  ip_address  = "192.168.10.3/24"
  gateway     = var.default_gateway
  dns_servers = ["1.1.1.1", "8.8.8.8"]
  
  disk_size = 8
  cpu_cores = 1
  memory    = 2048
  swap      = 2048
}

module "npm" {
  source = "../modules/lxc"

  node_name   = var.node_name
  hostname    = "npm"
  vm_id       = 104
  description = "Nginx Proxy Manager"
  template    = var.default_template
  os_type     = var.default_os_type
  ip_address  = "192.168.10.4/24"
  gateway     = var.default_gateway
  dns_servers = var.default_dns
  
  disk_size = 8
  cpu_cores = 1
  memory    = 2048
  swap      = 2048
}

module "tailscale" {
  source = "../modules/lxc"

  node_name   = var.node_name
  hostname    = "tailscale"
  vm_id       = 105
  description = "Tailscale Mesh Network"
  template    = var.default_template
  os_type     = var.default_os_type
  ip_address  = "192.168.10.5/24"
  gateway     = var.default_gateway
  dns_servers = var.default_dns
  
  disk_size = 8
  cpu_cores = 1
  memory    = 2048
  swap      = 2048
  keyctl    = true
}

module "cf_tunnel" {
  source = "../modules/lxc"

  node_name   = var.node_name
  hostname    = "cf-tunnel"
  vm_id       = 107
  description = "Cloudflare Tunnel"
  template    = var.default_template
  os_type     = var.default_os_type
  ip_address  = "192.168.10.7/24"
  gateway     = var.default_gateway
  dns_servers = var.default_dns
  
  disk_size = 8
  cpu_cores = 1
  memory    = 2048
  swap      = 2048
}
