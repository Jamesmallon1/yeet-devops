locals {
  name = "yeet-${var.env}"

  # private network
  net_cidr     = "10.10.0.0/16"
  subnet_cidr  = "10.10.1.0/24"
  monolith_ip  = "10.10.1.10"
  timescale_ip = "10.10.1.20"

  # hostnames
  api_host     = "api.${var.domain}"
  ws_host      = "ws.${var.domain}"
  ssh_host     = "ssh.${var.domain}"
  grafana_host = "grafana.${var.domain}"
  images_host  = "images.${var.domain}"

  backend_port = 8080

  labels = {
    project = "yeet"
    env     = var.env
    managed = "terraform"
  }
}
