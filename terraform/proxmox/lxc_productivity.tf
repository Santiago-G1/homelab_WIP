module "vaultwarden" {
  source     = "../modules/lxc"
  hostname   = "vaultwarden"
  vm_id      = 125
  ip_address = "192.168.10.23"
  cpu_cores  = 1
  memory     = 256
  swap       = 512
  disk_size  = 1
  keyctl     = true
}

module "radicale" {
  source     = "../modules/lxc"
  hostname   = "radicale"
  vm_id      = 114
  ip_address = "192.168.10.24"
  cpu_cores  = 1
  memory     = 512
  swap       = 512
  disk_size  = 2
  keyctl     = true
}

module "cloud-service" {
  source     = "../modules/lxc"
  hostname   = "cloud-service"
  vm_id      = 128
  ip_address = "192.168.10.25"
  cpu_cores  = 2
  memory     = 2048

  mount_points = [
    { volume = "/tank/cloud", mount_path = "/mnt/data/cloud" },
    { volume = "/tank/obsidian", mount_path = "/mnt/data/obsidian" },
  ]
}
