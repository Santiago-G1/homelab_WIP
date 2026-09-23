# AI stack (ComfyUI / llama-swap / LiteLLM / SillyTavern) -> the "llm" container.
# Needs GPU passthrough (/dev/nvidia*), which this module does not cover yet.
module "ai" {
  source     = "../modules/lxc"
  hostname   = "AI"
  vm_id      = 101
  ip_address = "192.168.10.26"
  cpu_cores  = 4
  memory     = 12288
  swap       = 9192
  disk_size  = 78

  mount_points = [
    { volume = "/tank/cloud/llm", mount_path = "/mnt/data" },
    { volume = "/tank/obsidian", mount_path = "/mnt/obsidian" },
  ]
}
