# ---------------- zone hygiene ----------------
resource "cloudflare_zone_setting" "ssl" {
  zone_id    = var.cloudflare_zone_id
  setting_id = "ssl"
  value      = "strict"
}

resource "cloudflare_zone_setting" "min_tls" {
  zone_id    = var.cloudflare_zone_id
  setting_id = "min_tls_version"
  value      = "1.2"
}

resource "cloudflare_zone_setting" "always_https" {
  zone_id    = var.cloudflare_zone_id
  setting_id = "always_use_https"
  value      = "on"
}

resource "cloudflare_zone_setting" "websockets" {
  zone_id    = var.cloudflare_zone_id
  setting_id = "websockets"
  value      = "on"
}

resource "cloudflare_zone_setting" "brotli" {
  zone_id    = var.cloudflare_zone_id
  setting_id = "brotli"
  value      = "on"
}

# ---------------- custom WAF rules (all plans) ----------------
# Only the paths the backend actually serves may reach it; anything else is dropped at the edge.
# Bot protection for /tokens/launch is Turnstile (widget in the frontend, token verified by the backend):
# a managed challenge cannot be solved by a fetch() call, and cf.bot_management.score is Enterprise-only.
resource "cloudflare_ruleset" "waf_custom" {
  zone_id     = var.cloudflare_zone_id
  name        = "${local.name}-waf-custom"
  description = "Allow-list of backend paths/methods; block the rest before it reaches the tunnel"
  kind        = "zone"
  phase       = "http_request_firewall_custom"

  rules = [
    {
      ref         = "block_unknown_api_paths"
      description = "api: only /api/v1/* and /healthz"
      expression  = "(http.host eq \"${local.api_host}\" and not starts_with(http.request.uri.path, \"/api/v1/\") and http.request.uri.path ne \"/healthz\")"
      action      = "block"
      enabled     = true
    },
    {
      ref         = "block_unknown_api_methods"
      description = "api: GET/POST/OPTIONS only"
      expression  = "(http.host eq \"${local.api_host}\" and not http.request.method in {\"GET\" \"POST\" \"OPTIONS\"})"
      action      = "block"
      enabled     = true
    },
    {
      ref         = "block_unknown_ws_paths"
      description = "ws: only /ws"
      expression  = "(http.host eq \"${local.ws_host}\" and http.request.uri.path ne \"/ws\")"
      action      = "block"
      enabled     = true
    },
  ]
}

# ---------------- rate limiting ----------------
# NOTE: Free plan allows 1 rate-limiting rule, Pro 2 (we are on Pro), Business 5. Most specific first.
resource "cloudflare_ruleset" "rate_limit" {
  zone_id     = var.cloudflare_zone_id
  name        = "${local.name}-ratelimit"
  description = "Per-IP limits on the backend"
  kind        = "zone"
  phase       = "http_ratelimit"

  rules = [
    {
      ref         = "rl_launch"
      description = "token launch uploads: 5 per minute per IP"
      expression  = "(http.host eq \"${local.api_host}\" and http.request.uri.path eq \"/api/v1/tokens/launch\")"
      action      = "block"
      enabled     = true
      ratelimit = {
        characteristics     = ["ip.src", "cf.colo.id"]
        period              = 60
        requests_per_period = 5
        mitigation_timeout  = 600
      }
    },
    {
      ref         = "rl_backend"
      description = "api + ws: 300 requests per minute per IP (ws handshakes count as requests)"
      expression  = "(http.host in {\"${local.api_host}\" \"${local.ws_host}\"})"
      action      = "block"
      enabled     = true
      ratelimit = {
        characteristics     = ["ip.src", "cf.colo.id"]
        period              = 60
        requests_per_period = 300
        mitigation_timeout  = 60
      }
    },
  ]
}

# ---------------- managed WAF (Pro+) ----------------
resource "cloudflare_ruleset" "waf_managed" {
  count = var.enable_managed_waf ? 1 : 0

  zone_id     = var.cloudflare_zone_id
  name        = "${local.name}-waf-managed"
  description = "Cloudflare Managed + OWASP rulesets on backend hosts"
  kind        = "zone"
  phase       = "http_request_firewall_managed"

  rules = [
    {
      # multipart image uploads trip the managed rules (body anomaly). The backend validates and re-encodes every
      # upload and the route is behind Turnstile + a 5/min rate limit, so skip managed rules for this one path.
      ref         = "skip_managed_for_launch"
      description = "skip managed WAF for the token launch upload"
      expression  = "(http.host eq \"${local.api_host}\" and http.request.uri.path eq \"/api/v1/tokens/launch\" and http.request.method eq \"POST\")"
      action      = "skip"
      enabled     = true
      action_parameters = {
        ruleset = "current"
      }
      logging = { enabled = true }
    },
    {
      ref         = "cf_managed"
      description = "Cloudflare Managed Ruleset"
      expression  = "(http.host in {\"${local.api_host}\" \"${local.ws_host}\"})"
      action      = "execute"
      enabled     = true
      action_parameters = {
        id = "efb7b8c949ac4650a09736fc376e9aee"
      }
    },
    {
      ref         = "owasp"
      description = "OWASP Core Ruleset"
      expression  = "(http.host in {\"${local.api_host}\" \"${local.ws_host}\"})"
      action      = "execute"
      enabled     = true
      action_parameters = {
        id = "4814384a9e5d4991b9815dcfc25d2f1f"
      }
    },
  ]
}

# ---------------- edge cache for GET endpoints ----------------
# Backend sends Cache-Control: public, max-age=1 on list/detail GETs; this tells CF to honour it
# for the API host (Cloudflare does not cache JSON by default).
resource "cloudflare_ruleset" "cache" {
  zone_id     = var.cloudflare_zone_id
  name        = "${local.name}-cache"
  description = "Cache eligible API GETs at the edge per origin headers"
  kind        = "zone"
  phase       = "http_request_cache_settings"

  rules = [
    {
      ref         = "cache_api_gets"
      description = "api GETs: cache per origin Cache-Control, 1s default"
      expression  = "(http.host eq \"${local.api_host}\" and http.request.method eq \"GET\" and not http.request.uri.query contains \"wallet_address=\")"
      action      = "set_cache_settings"
      enabled     = true
      action_parameters = {
        cache = true
        edge_ttl = {
          mode = "respect_origin"
        }
        browser_ttl = {
          mode = "respect_origin"
        }
      }
    },
  ]
}

# ---------------- R2 for token images ----------------
resource "cloudflare_r2_bucket" "images" {
  count         = var.enable_r2 ? 1 : 0
  account_id    = var.cloudflare_account_id
  name          = "yeet-images-${var.env}"
  location      = "enam"
  storage_class = "Standard"
}

resource "cloudflare_r2_custom_domain" "images" {
  count       = var.enable_r2 ? 1 : 0
  account_id  = var.cloudflare_account_id
  bucket_name = cloudflare_r2_bucket.images[0].name
  domain      = local.images_host
  zone_id     = var.cloudflare_zone_id
  enabled     = true
  min_tls     = "1.2"
}

# ---------------- Pages for the Next.js frontend ----------------
resource "cloudflare_pages_project" "frontend" {
  count             = var.enable_pages ? 1 : 0
  account_id        = var.cloudflare_account_id
  name              = "yeet-frontend"
  production_branch = "main"

  build_config = {
    build_command   = "pnpm build" # static export (next.config output: "export")
    destination_dir = "out"
    root_dir        = "/"
  }

  source = var.pages_github == null ? null : {
    type = "github"
    config = {
      owner                          = var.pages_github.owner
      repo_name                      = var.pages_github.repo_name
      repo_id                        = var.pages_github.repo_id
      owner_id                       = var.pages_github.owner_id
      production_branch              = "main"
      production_deployments_enabled = true
      preview_deployment_setting     = "all"
    }
  }

  deployment_configs = {
    production = {
      compatibility_date  = "2026-09-01"
      compatibility_flags = ["nodejs_compat"]
      env_vars = {
        NEXT_PUBLIC_YEET_CHAIN         = { type = "plain_text", value = var.yeet_chain }
        NEXT_PUBLIC_API_URL            = { type = "plain_text", value = "https://${local.api_host}" }
        NEXT_PUBLIC_WS_URL             = { type = "plain_text", value = "wss://${local.ws_host}/ws" }
        NEXT_PUBLIC_IMAGES_URL         = { type = "plain_text", value = "https://${local.images_host}" }
        NEXT_PUBLIC_TURNSTILE_SITE_KEY = { type = "plain_text", value = var.turnstile_site_key }
        NEXT_PUBLIC_STACK              = { type = "plain_text", value = "lite" }
      }
    }
    preview = {
      compatibility_date  = "2026-09-01"
      compatibility_flags = ["nodejs_compat"]
      env_vars = {
        NEXT_PUBLIC_YEET_CHAIN         = { type = "plain_text", value = "arc-testnet" }
        NEXT_PUBLIC_API_URL            = { type = "plain_text", value = "https://${local.api_host}" }
        NEXT_PUBLIC_WS_URL             = { type = "plain_text", value = "wss://${local.ws_host}/ws" }
        NEXT_PUBLIC_IMAGES_URL         = { type = "plain_text", value = "https://${local.images_host}" }
        NEXT_PUBLIC_TURNSTILE_SITE_KEY = { type = "plain_text", value = var.turnstile_site_key }
        NEXT_PUBLIC_STACK              = { type = "plain_text", value = "lite" }
      }
    }
  }
}

resource "cloudflare_pages_domain" "apex" {
  count        = var.enable_pages ? 1 : 0
  account_id   = var.cloudflare_account_id
  project_name = cloudflare_pages_project.frontend[0].name
  name         = var.domain
}

resource "cloudflare_pages_domain" "www" {
  count        = var.enable_pages ? 1 : 0
  account_id   = var.cloudflare_account_id
  project_name = cloudflare_pages_project.frontend[0].name
  name         = "www.${var.domain}"
}

resource "cloudflare_dns_record" "apex" {
  count   = var.enable_pages ? 1 : 0
  zone_id = var.cloudflare_zone_id
  name    = var.domain
  type    = "CNAME"
  content = cloudflare_pages_project.frontend[0].subdomain
  proxied = true
  ttl     = 1
}

resource "cloudflare_dns_record" "www" {
  count   = var.enable_pages ? 1 : 0
  zone_id = var.cloudflare_zone_id
  name    = "www.${var.domain}"
  type    = "CNAME"
  content = cloudflare_pages_project.frontend[0].subdomain
  proxied = true
  ttl     = 1
}
