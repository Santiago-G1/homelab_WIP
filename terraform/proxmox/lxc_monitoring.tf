module "monitoring" {
  source = "../modules/lxc"
  hostname    = "monitoring"
  vm_id       = 110
  ip_address  = "192.168.10.10"
  cpu_cores = 2
  memory    = 4096
}
