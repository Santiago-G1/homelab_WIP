module "adguard" {
  source      = "../modules/lxc"
  hostname    = "adguard"
  vm_id       = 103
  ip_address  = "192.168.10.3"
  default_dns = ["1.1.1.1"]
}

module "npm" {
  source      = "../modules/lxc"
  hostname    = "npm"
  vm_id       = 104
  ip_address  = "192.168.10.4"
}

module "tailscale" {
  source      = "../modules/lxc"
  hostname    = "tailscale"
  vm_id       = 105
  ip_address  = "192.168.10.5"
}

module "cf_tunnel" {
  source      = "../modules/lxc"
  hostname    = "cf-tunnel"
  vm_id       = 107
  ip_address  = "192.168.10.6"
}
