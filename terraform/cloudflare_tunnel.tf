# One tunnel, outbound from the monolith. This is the ONLY way traffic reaches the backend,
# so every request has already passed Cloudflare's WAF, rate limits, bot rules and DDoS protection.

resource "random_id" "tunnel_secret" {
  byte_length = 32
}

resource "cloudflare_zero_trust_tunnel_cloudflared" "main" {
  account_id    = var.cloudflare_account_id
  name          = "${local.name}-monolith"
  config_src    = "cloudflare"
  tunnel_secret = random_id.tunnel_secret.b64_std

  lifecycle {
    ignore_changes = [tunnel_secret] # state was rebuilt once; a new local secret must not replace the live tunnel
  }
}

data "cloudflare_zero_trust_tunnel_cloudflared_token" "main" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.main.id
}

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "main" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.main.id

  config = {
    ingress = concat([
      {
        hostname = local.api_host
        service  = "http://localhost:${local.backend_port}"
        origin_request = {
          connect_timeout        = 5
          keep_alive_connections = 512
          keep_alive_timeout     = 90
          tcp_keep_alive         = 30
          http2_origin           = false
        }
      },
      {
        hostname = local.ws_host
        service  = "http://localhost:${local.backend_port}"
        origin_request = {
          connect_timeout        = 5
          keep_alive_connections = 4096
          keep_alive_timeout     = 90
          tcp_keep_alive         = 30
        }
      },
      ],
      var.enable_access ? [
        { hostname = local.grafana_host, service = "http://localhost:3000" },
        { hostname = local.ssh_host, service = "ssh://localhost:22" },
      ] : [],
      [{ service = "http_status:404" }]
    )
  }
}

# DNS: proxied CNAMEs to the tunnel
resource "cloudflare_dns_record" "tunnel" {
  for_each = toset(concat([local.api_host, local.ws_host], var.enable_access ? [local.grafana_host, local.ssh_host] : []))

  zone_id = var.cloudflare_zone_id
  name    = each.value
  type    = "CNAME"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.main.id}.cfargotunnel.com"
  proxied = true
  ttl     = 1
  comment = "managed by terraform (yeet-devops)"
}
