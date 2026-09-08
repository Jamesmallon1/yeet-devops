# ---------------- SSH key ----------------
resource "hcloud_ssh_key" "admin" {
  name       = "${local.name}-admin"
  public_key = var.ssh_public_key
  labels     = local.labels
}

# ---------------- private network ----------------
resource "hcloud_network" "main" {
  name     = "${local.name}-net"
  ip_range = local.net_cidr
  labels   = local.labels
}

resource "hcloud_network_subnet" "main" {
  network_id   = hcloud_network.main.id
  type         = "cloud"
  network_zone = var.hetzner_network_zone
  ip_range     = local.subnet_cidr
}

# ---------------- firewalls (public interface only; private net is unfiltered by hcloud) ----------------
# Monolith: NO inbound from the internet. Everything arrives via the outbound Cloudflare Tunnel.
resource "hcloud_firewall" "monolith" {
  name   = "${local.name}-monolith"
  labels = local.labels

  # Optional break-glass SSH from fixed admin IPs only.
  dynamic "rule" {
    for_each = length(var.emergency_admin_cidrs) > 0 ? [1] : []
    content {
      direction  = "in"
      protocol   = "tcp"
      port       = "22"
      source_ips = var.emergency_admin_cidrs
    }
  }

  # ICMP for path MTU / diagnostics
  rule {
    direction  = "in"
    protocol   = "icmp"
    source_ips = ["0.0.0.0/0", "::/0"]
  }
}

# Timescale: nothing inbound at all on the public side.
resource "hcloud_firewall" "timescale" {
  name   = "${local.name}-timescale"
  labels = local.labels

  rule {
    direction  = "in"
    protocol   = "icmp"
    source_ips = ["0.0.0.0/0", "::/0"]
  }
}

# ---------------- passwords ----------------
resource "random_password" "timescale_indexer" {
  length  = 32
  special = false
}

resource "random_password" "timescale_api" {
  length  = 32
  special = false
}

resource "random_password" "timescale_superuser" {
  length  = 32
  special = false
}

resource "random_password" "appdb" {
  length  = 32
  special = false
}

resource "random_password" "grafana_admin" {
  length  = 24
  special = false
}

# ---------------- servers ----------------
resource "hcloud_placement_group" "spread" {
  name   = "${local.name}-spread"
  type   = "spread"
  labels = local.labels
}

resource "hcloud_server" "timescale" {
  name               = "${local.name}-timescale"
  server_type        = var.timescale_server_type
  image              = var.image
  location           = var.hetzner_location
  ssh_keys           = [hcloud_ssh_key.admin.id]
  firewall_ids       = [hcloud_firewall.timescale.id]
  placement_group_id = hcloud_placement_group.spread.id
  labels             = merge(local.labels, { role = "timescale" })

  # No public IPv4. IPv6 only, used for outbound (apt, docker pulls). Nothing listens on it.
  public_net {
    ipv4_enabled = false
    ipv6_enabled = true
  }

  network {
    network_id = hcloud_network.main.id
    ip         = local.timescale_ip
  }

  user_data = templatefile("${path.module}/templates/cloud-init-timescale.yaml.tftpl", {
    private_ip         = local.timescale_ip
    monolith_ip        = local.monolith_ip
    superuser_password = random_password.timescale_superuser.result
    indexer_password   = random_password.timescale_indexer.result
    api_password       = random_password.timescale_api.result
    compose_file       = file("${path.module}/../compose/timescale/docker-compose.yml")
    postgresql_conf    = file("${path.module}/../compose/timescale/postgresql.conf")
    pg_hba_conf        = templatefile("${path.module}/../compose/timescale/pg_hba.conf.tftpl", { monolith_ip = local.monolith_ip })
    init_roles_sql     = file("${path.module}/../compose/timescale/init/01-roles.sql")
  })

  depends_on = [hcloud_network_subnet.main]

  lifecycle {
    ignore_changes = [user_data] # cloud-init runs once; later changes go through scripts/deploy.sh
  }
}

resource "hcloud_server" "monolith" {
  name               = "${local.name}-monolith"
  server_type        = var.monolith_server_type
  image              = var.image
  location           = var.hetzner_location
  ssh_keys           = [hcloud_ssh_key.admin.id]
  firewall_ids       = [hcloud_firewall.monolith.id]
  placement_group_id = hcloud_placement_group.spread.id
  labels             = merge(local.labels, { role = "monolith" })

  public_net {
    ipv4_enabled = true # needed for the outbound tunnel + RPC egress; nothing listens on it
    ipv6_enabled = true
  }

  network {
    network_id = hcloud_network.main.id
    ip         = local.monolith_ip
  }

  user_data = templatefile("${path.module}/templates/cloud-init-monolith.yaml.tftpl", {
    private_ip          = local.monolith_ip
    timescale_ip        = local.timescale_ip
    tunnel_token        = data.cloudflare_zero_trust_tunnel_cloudflared_token.main.token
    backend_image       = var.backend_image
    ghcr_username       = var.ghcr_username
    ghcr_token          = var.ghcr_token
    yeet_chain          = var.yeet_chain
    quicknode_http      = var.quicknode_http
    quicknode_ws        = var.quicknode_ws
    pinata_jwt          = var.pinata_jwt
    r2_bucket           = var.enable_r2 ? cloudflare_r2_bucket.images[0].name : "yeet-images-${var.env}"
    r2_account_id       = var.cloudflare_account_id
    images_host         = local.images_host
    appdb_password      = random_password.appdb.result
    ts_indexer_password = random_password.timescale_indexer.result
    ts_api_password     = random_password.timescale_api.result
    grafana_password    = random_password.grafana_admin.result
    grafana_host        = local.grafana_host
    backend_port        = local.backend_port
    compose_file        = file("${path.module}/../compose/monolith/docker-compose.yml")
    prometheus_yml      = file("${path.module}/../compose/monolith/prometheus.yml")
  })

  depends_on = [hcloud_network_subnet.main, hcloud_server.timescale]

  lifecycle {
    ignore_changes = [user_data]
  }
}
