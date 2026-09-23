module "arrsuite" {
  source       = "../modules/lxc"
  hostname     = "arrsuite"
  vm_id        = 120
  ip_address   = "192.168.10.20"
  cpu_cores    = 2
  memory       = 4096
  swap         = 4096
  disk_size    = 36
  mount_volume = "/tank/media"
}

module "immich" {
  source       = "../modules/lxc"
  hostname     = "immich"
  vm_id        = 126
  ip_address   = "192.168.10.22"
  cpu_cores    = 4
  memory       = 6144
  swap         = 2048
  disk_size    = 30
  keyctl       = true
  mount_volume = "/tank/immich"
  mount_point  = "/mnt/immich"
}

module "frontend" {
  source       = "../modules/lxc"
  hostname     = "frontend"
  vm_id        = 123
  ip_address   = "192.168.10.21"
  cpu_cores    = 2
  memory       = 4096
  swap         = 2048
  disk_size    = 16
  mount_volume = "/tank/media"
  mount_point  = "/mnt/media"
}
