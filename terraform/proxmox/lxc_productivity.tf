module "vaultwarden" {
  source     = "../modules/lxc"
  hostname   = "vaultwarden"
  vm_id      = 125
  ip_address = "192.168.10.23"
}

module "radicale" {
  source     = "../modules/lxc"
  hostname   = "radicale"
  vm_id      = 114
  ip_address = "192.168.10.24"
}

module "cloud-service" {
  source       = "../modules/lxc"
  hostname     = "cloud-service"
  vm_id        = 117
  ip_address   = "192.168.10.25"
  mount_volume = "/tank/cloud"
}
