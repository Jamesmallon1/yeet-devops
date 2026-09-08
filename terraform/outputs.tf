output "monolith_public_ipv4" {
  value = hcloud_server.monolith.ipv4_address
}

output "monolith_private_ip" {
  value = local.monolith_ip
}

output "timescale_private_ip" {
  value = local.timescale_ip
}

output "tunnel_id" {
  value = cloudflare_zero_trust_tunnel_cloudflared.main.id
}

output "ssh_hint" {
  value = var.enable_access ? "scripts/ssh.sh monolith" : "ssh root@${hcloud_server.monolith.ipv4_address}  (break-glass, from emergency_admin_cidrs only)"
}

output "hostnames" {
  value = {
    api     = local.api_host
    ws      = local.ws_host
    ssh     = local.ssh_host
    grafana = local.grafana_host
    images  = local.images_host
    app     = var.domain
  }
}

output "timescale_passwords" {
  sensitive = true
  value = {
    superuser = random_password.timescale_superuser.result
    indexer   = random_password.timescale_indexer.result
    api       = random_password.timescale_api.result
  }
}

output "appdb_password" {
  sensitive = true
  value     = random_password.appdb.result
}

output "grafana_admin_password" {
  sensitive = true
  value     = random_password.grafana_admin.result
}
