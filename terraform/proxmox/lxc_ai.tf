# AI stack (ComfyUI / LiteLLM) -> the "llm" container.
# The GPU is passed through with device_passthrough; the NVIDIA driver lives inside the container.
module "ai" {
  source     = "../modules/lxc"
  hostname   = "AI"
  vm_id      = 126
  ip_address = "192.168.10.26"
  cpu_cores  = 4
  memory     = 12288
  swap       = 9192
  disk_size  = 78

  # PVE creates the device nodes root:root 0660, which the unprivileged
  # llama-server user (member of the container's video group) cannot open.
  # gid is the container-side id, so video = 44.
  device_passthrough = [
    { path = "/dev/nvidia0", gid = 44 },
    { path = "/dev/nvidiactl", gid = 44 },
    { path = "/dev/nvidia-uvm", gid = 44 },
    { path = "/dev/nvidia-uvm-tools", gid = 44 },
  ]

  mount_points = [
    { volume = "/tank/cloud/llm", mount_path = "/mnt/data" },
    { volume = "/tank/obsidian", mount_path = "/mnt/obsidian", read_only = true },
  ]
}
