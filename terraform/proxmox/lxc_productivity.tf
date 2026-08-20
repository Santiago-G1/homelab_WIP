module "vaultwarden" {
  source      = "../modules/lxc"
  hostname    = "vaultwarden"
  vm_id       = 125
  ip_address  = "192.168.10.25"
}

module "radicale" {
  source      = "../modules/lxc"
  hostname    = "radicale"
  vm_id       = 114
  ip_address  = "192.168.10.14"
}


module "cloud-service" {
  source        = "../modules/lxc"
  hostname      = "cloud-service"
  vm_id         = 117
  ip_address    = "192.168.10.17"
  mount_storage = "tank"
  mount_volume  = "/tank/cloud"
}
