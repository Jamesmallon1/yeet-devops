#!/usr/bin/env bash
# ssh through the Cloudflare tunnel (Access-gated). Usage: scripts/ssh.sh monolith|timescale [cmd...]
set -euo pipefail
DOMAIN="${YEET_DOMAIN:-yeet.family}"
TARGET="${1:-monolith}"; shift || true
PROXY="cloudflared access ssh --hostname ssh.$DOMAIN"
case "$TARGET" in
  monolith)  exec ssh -o ProxyCommand="$PROXY" -o StrictHostKeyChecking=accept-new root@ssh.$DOMAIN "$@" ;;
  timescale) exec ssh -o ProxyCommand="ssh -o ProxyCommand='$PROXY' -W %h:%p root@ssh.$DOMAIN" \
                      -o StrictHostKeyChecking=accept-new root@10.10.1.20 "$@" ;;
  *) echo "monolith|timescale"; exit 1 ;;
esac
