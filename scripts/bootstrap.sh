#!/usr/bin/env bash
# One-time: create infra. Requires: terraform, hcloud (for sanity), cloudflared, and env vars:
#   TF_VAR_hcloud_token TF_VAR_cloudflare_api_token TF_VAR_ghcr_token TF_VAR_quicknode_http TF_VAR_quicknode_ws TF_VAR_pinata_jwt
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[[ -f "$ROOT/secrets.env" ]] && source "$ROOT/secrets.env"
cd "$ROOT/terraform"

for v in TF_VAR_hcloud_token TF_VAR_cloudflare_api_token TF_VAR_ghcr_token; do
  [[ -n "${!v:-}" ]] || { echo "missing $v (put it in secrets.env)"; exit 1; }
done
[[ -f terraform.tfvars ]] || { echo "copy terraform.tfvars.example -> terraform.tfvars and fill it"; exit 1; }

terraform init
terraform fmt -check -recursive || terraform fmt -recursive
terraform validate
terraform plan -out=tfplan
if [[ "${1:-}" != "--yes" ]]; then read -r -p "apply? [y/N] " ok; [[ "$ok" == "y" ]] || exit 0; fi
terraform apply tfplan
terraform output
echo
echo "Next: scripts/ssh.sh monolith  →  docker compose ps ; cloud-init status --wait"
