#!/usr/bin/env bash
# Deploy a backend image tag to the monolith. Usage: scripts/deploy.sh v0.3.1   (or a sha tag)
set -euo pipefail
TAG="${1:?image tag}"
IMAGE="ghcr.io/jamesmallon1/yeet-backend:$TAG"
HERE="$(cd "$(dirname "$0")" && pwd)"
"$HERE/ssh.sh" monolith bash -s <<REMOTE
set -euo pipefail
cd /opt/yeet
sed -i "s#^BACKEND_IMAGE=.*#BACKEND_IMAGE=$IMAGE#" .env
docker compose --env-file .env pull backend
docker compose --env-file .env up -d backend
for i in \$(seq 1 30); do
  if curl -fsS http://127.0.0.1:8080/healthz >/dev/null 2>&1; then echo "healthy: $IMAGE"; exit 0; fi
  sleep 2
done
echo "backend not healthy after 60s"; docker logs --tail 100 yeet-backend; exit 1
REMOTE
