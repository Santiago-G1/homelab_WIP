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

  # iGPU (VAAPI) and P100 (NVENC/CUDA). gid is the container-side group of
  # immich-server (999:991, see the Compose override).
  device_passthrough = [
    { path = "/dev/dri/renderD128", gid = 991 },
    { path = "/dev/nvidia0", gid = 991 },
    { path = "/dev/nvidiactl", gid = 991 },
    { path = "/dev/nvidia-uvm", gid = 991 },
    { path = "/dev/nvidia-uvm-tools", gid = 991 },
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

  # iGPU (VAAPI) and P100 (NVENC/NVDEC); gid 44 matches the Compose group_add.
  device_passthrough = [
    { path = "/dev/dri/renderD128", gid = 44 },
    { path = "/dev/nvidia0", gid = 44 },
    { path = "/dev/nvidiactl", gid = 44 },
    { path = "/dev/nvidia-uvm", gid = 44 },
    { path = "/dev/nvidia-uvm-tools", gid = 44 },
  ]
}
