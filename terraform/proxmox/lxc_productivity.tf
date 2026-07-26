module "vaultwarden" {
  source = "../modules/lxc"
  hostname    = "vaultwarden"
  vm_id       = 125
  ip_address  = "192.168.10.25"
}

module "radicale" {
  source = "../modules/lxc"
  hostname    = "radicale"
  vm_id       = 114
  ip_address  = "192.168.10.14"
}

module "syncthing" {
  source = "../modules/lxc"
  hostname    = "syncthing"
  vm_id       = 115
  ip_address  = "192.168.10.15"
  mount_volume = "/tank/obsidian1"
}


module "filebrowser" {
  source = "../modules/lxc"
  hostname    = "filebrowser"
  vm_id       = 117
  ip_address  = "192.168.10.17"
  mount_volume = "/tank/cloud"
}
