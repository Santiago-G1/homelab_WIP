module "arrsuite" {
  source        = "../modules/lxc"
  hostname      = "arrsuite"
  vm_id         = 120
  ip_address    = "192.168.10.20"
  cpu_cores     = 2
  memory        = 4096
  mount_storage = "tank"
  mount_volume  = "/tank/media"
}

module "immich" {
  source        = "../modules/lxc"
  hostname      = "immich"
  vm_id         = 126
  ip_address    = "192.168.10.22"
  disk_size     = 20
  cpu_cores     = 3
  memory        = 6144
  mount_storage = "tank"
  mount_volume  = "/tank/immich"
}

module "frontend" {
  source        = "../modules/lxc"
  hostname      = "frontend"
  vm_id         = 123
  ip_address    = "192.168.10.21"
  disk_size     = 8
  cpu_cores     = 2
  mount_storage = "tank"
  mount_volume  = "/tank/media"
}
