# AI stack (ComfyUI / llama-swap / LiteLLM / SillyTavern) -> the "llm" container.
# Reality also needs GPU passthrough (/dev/nvidia*) and a second read-only
# bind mount, which this module cannot express yet.
module "ai" {
  source       = "../modules/lxc"
  hostname     = "AI"
  vm_id        = 101
  ip_address   = "192.168.10.26"
  cpu_cores    = 4
  memory       = 12288
  swap         = 9192
  disk_size    = 78
  mount_volume = "/tank/cloud/llm"
}
