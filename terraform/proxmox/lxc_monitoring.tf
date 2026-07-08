module "monitoring" {
  source = "../modules/lxc"

  node_name   = var.node_name
  hostname    = "monitoring"
  vm_id       = 110
  description = "Prometheus + Grafana + Loki Observability Stack"
  template    = var.default_template
  os_type     = var.default_os_type
  ip_address  = "192.168.10.10/24"
  gateway     = var.default_gateway
  dns_servers = var.default_dns
  
  disk_size = 8
  cpu_cores = 2
  memory    = 4096
  swap      = 2048
}
