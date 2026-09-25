module "blocky" {
  source      = "../modules/lxc"
  hostname    = "adguard"
  vm_id       = 103
  ip_address  = "192.168.10.3"
  cpu_cores   = 2
  memory      = 1024
  swap        = 1024
  disk_size   = 7
  default_dns = ["1.1.1.1"]
}

module "caddy" {
  source     = "../modules/lxc"
  hostname   = "npm"
  vm_id      = 104
  ip_address = "192.168.10.4"
  cpu_cores  = 2
  memory     = 1048
  swap       = 512
}

module "tailscale" {
  source     = "../modules/lxc"
  hostname   = "tailscale"
  vm_id      = 105
  ip_address = "192.168.10.5"
  cpu_cores  = 1
  memory     = 512
  swap       = 512
  keyctl     = true

  # Tailscale is wireguard based and needs the TUN device; the original
  # container had the same passthrough as raw lxc.mount.entry lines.
  device_passthrough = [
    { path = "/dev/net/tun" },
  ]
}

module "cf_tunnel" {
  source     = "../modules/lxc"
  hostname   = "cf-tunnel"
  vm_id      = 106
  ip_address = "192.168.10.6"
  cpu_cores  = 1
  memory     = 1024
  swap       = 1024
}
