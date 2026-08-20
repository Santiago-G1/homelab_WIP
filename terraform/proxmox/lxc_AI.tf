module "AI" {
  source        = "../modules/lxc"
  hostname      = "AI"
  vm_id         = 109
  ip_address    = "192.168.10.9"
  cpu_cores     = 4
  memory        = 6192
  mount_storage = "tank"
  mount_volume  = "/tank/cloud"
}

