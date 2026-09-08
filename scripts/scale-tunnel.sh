#!/usr/bin/env bash
# More tunnel replicas = more websocket capacity through Cloudflare. Usage: scripts/scale-tunnel.sh 3
set -euo pipefail
N="${1:-2}"
"$(dirname "$0")/ssh.sh" monolith "cd /opt/yeet && docker compose --env-file .env up -d --scale cloudflared=$N --no-recreate"
