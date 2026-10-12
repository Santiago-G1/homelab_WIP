module "arrsuite" {
  source     = "../modules/lxc"
  hostname   = "arrsuite"
  vm_id      = 120
  ip_address = "192.168.10.20"
  cpu_cores  = 2
  memory     = 4096
  swap       = 4096
  disk_size  = 36

  mount_points = [
    { volume = "/tank/media", mount_path = "/mnt/data" },
  ]
}

module "immich" {
  source     = "../modules/lxc"
  hostname   = "immich"
  vm_id      = 122
  ip_address = "192.168.10.22"
  cpu_cores  = 4
  memory     = 6144
  swap       = 2048
  disk_size  = 30
  keyctl     = true

  mount_points = [
    { volume = "/tank/immich", mount_path = "/mnt/immich" },
  ]

  # Intel iGPU render node for VAAPI transcoding. gid is the container-side id
  # of the group immich-server runs as (999:991, see the Compose override), so
  # the device is readable for it without widening the mode.
  device_passthrough = [
    { path = "/dev/dri/renderD128", gid = 991 },
  ]
}

module "frontend" {
  source     = "../modules/lxc"
  hostname   = "frontend"
  vm_id      = 121
  ip_address = "192.168.10.21"
  cpu_cores  = 2
  memory     = 4096
  swap       = 2048
  disk_size  = 16

  mount_points = [
    { volume = "/tank/media", mount_path = "/mnt/media" },
  ]

  # Intel iGPU render node for Jellyfin VAAPI transcoding. Jellyfin runs as root
  # inside the container, which owns the node; gid 44 (video) holds the group
  # readable bit the render node already has on the host.
  device_passthrough = [
    { path = "/dev/dri/renderD128", gid = 44 },
  ]
}
