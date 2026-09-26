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

  device_passthrough = [
    { path = "/dev/nvidia0" },
    { path = "/dev/nvidiactl" },
    { path = "/dev/nvidia-uvm" },
    { path = "/dev/nvidia-uvm-tools" },
  ]

  mount_points = [
    { volume = "/tank/cloud/llm", mount_path = "/mnt/data" },
    { volume = "/tank/obsidian", mount_path = "/mnt/obsidian", read_only = true },
  ]
}
