# Zero Trust Access in front of SSH and Grafana. Only listed emails get through; the origin
# never sees an unauthenticated packet for these hostnames.

resource "cloudflare_zero_trust_access_policy" "admins" {
  count      = var.enable_access ? 1 : 0
  account_id = var.cloudflare_account_id
  name       = "${local.name}-admins"
  decision   = "allow"

  include = [for e in var.admin_emails : { email = { email = e } }]
}

resource "cloudflare_zero_trust_access_application" "ssh" {
  count            = var.enable_access ? 1 : 0
  account_id       = var.cloudflare_account_id
  name             = "${local.name}-ssh"
  domain           = local.ssh_host
  type             = "self_hosted"
  session_duration = "24h"

  policies = [{ id = cloudflare_zero_trust_access_policy.admins[0].id, precedence = 1 }]
}

resource "cloudflare_zero_trust_access_application" "grafana" {
  count            = var.enable_access ? 1 : 0
  account_id       = var.cloudflare_account_id
  name             = "${local.name}-grafana"
  domain           = local.grafana_host
  type             = "self_hosted"
  session_duration = "24h"

  policies = [{ id = cloudflare_zero_trust_access_policy.admins[0].id, precedence = 1 }]
}
