# ---------- credentials (never commit; use TF_VAR_* or terraform.tfvars ignored by git) ----------
variable "hcloud_token" {
  type      = string
  sensitive = true
}

variable "cloudflare_api_token" {
  type        = string
  sensitive   = true
  description = "Token with: Zone DNS/Settings/WAF edit, Account Cloudflare Tunnel edit, Access edit, R2 edit, Pages edit"
}

variable "cloudflare_account_id" { type = string }
variable "cloudflare_zone_id" { type = string }

# ---------- naming / placement ----------
variable "env" {
  type    = string
  default = "prod"
}

variable "domain" {
  type    = string
  default = "yeet.family"
}

variable "hetzner_location" {
  type        = string
  default     = "ash" # Ashburn, VA (us-east)
  description = "hcloud location"
}

variable "hetzner_network_zone" {
  type    = string
  default = "us-east"
}

variable "monolith_server_type" {
  type    = string
  default = "ccx33" # 8 dedicated vCPU / 32 GB / 240 GB NVMe
}

variable "timescale_server_type" {
  type    = string
  default = "ccx33"
}

variable "image" {
  type    = string
  default = "ubuntu-24.04"
}

# ---------- access ----------
variable "ssh_public_key" {
  type        = string
  description = "Your admin SSH public key (injected into both servers)"
}

variable "admin_emails" {
  type        = list(string)
  description = "Emails allowed through Cloudflare Access for ssh.<domain> and grafana.<domain>"
}

variable "emergency_admin_cidrs" {
  type        = list(string)
  default     = []
  description = "Optional: public CIDRs allowed to reach port 22 on the monolith's PUBLIC IP. Keep empty; SSH goes through the tunnel."
}

# ---------- app ----------
variable "backend_image" {
  type    = string
  default = "ghcr.io/jamesmallon1/yeet-backend:latest"
}

variable "ghcr_username" {
  type    = string
  default = "jamesmallon1"
}

variable "ghcr_token" {
  type        = string
  sensitive   = true
  description = "GitHub PAT with read:packages so the servers can pull the private backend image"
}

variable "yeet_chain" {
  type        = string
  default     = "arc-testnet"
  description = "arc-testnet | arc-mainnet  (the one switch)"
}

variable "quicknode_http" {
  type      = string
  sensitive = true
}

variable "quicknode_ws" {
  type      = string
  sensitive = true
}

variable "pinata_jwt" {
  type      = string
  sensitive = true
}

variable "enable_managed_waf" {
  type        = bool
  default     = false
  description = "Deploy Cloudflare Managed WAF rulesets (requires Pro plan or higher)"
}

variable "pages_github" {
  type = object({
    owner     = string
    repo_name = string
    repo_id   = string
    owner_id  = string
  })
  default     = null
  description = "Optional GitHub source for the Pages project. Requires the GitHub app to be connected in the dashboard first."
}

# ---------- feature flags (turn on as account capabilities/token scopes become available) ----------
variable "enable_access" {
  type        = bool
  default     = false
  description = "Zero Trust Access in front of ssh/grafana. Requires 'Enable Access' once in the Cloudflare dashboard."
}

variable "enable_r2" {
  type        = bool
  default     = false
  description = "R2 images bucket + custom domain. Requires token scope Workers R2 Storage:Edit."
}

variable "enable_pages" {
  type        = bool
  default     = false
  description = "Pages project + domains. Requires token scope Cloudflare Pages:Edit."
}

variable "turnstile_secret" {
  type      = string
  sensitive = true
  default   = ""
}

variable "turnstile_site_key" {
  type    = string
  default = ""
}

variable "reown_project_id" {
  type    = string
  default = ""
}

variable "posthog_project_token" {
  type    = string
  default = ""
}

variable "posthog_host" {
  type    = string
  default = "https://eu.i.posthog.com"
}

variable "yeet_token" {
  description = "Address of the protocol YEET token the home statement is built around"
  type        = string
  default     = "0xa8565fd7e62bd87829d4152e18342a2ebfa37442"
}
