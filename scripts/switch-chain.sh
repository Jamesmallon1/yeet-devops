#!/usr/bin/env bash
# The mainnet flip. Usage: scripts/switch-chain.sh arc-mainnet <image-tag-with-mainnet-deployments>
# Requires: a backend image whose deployments/5042.json is real, and terraform var yeet_chain updated
# (so Pages env + future rebuilds agree). Fresh databases: run scripts/reset-db.sh first (indexer replays).
set -euo pipefail
CHAIN="${1:?arc-testnet|arc-mainnet}"; TAG="${2:?image tag}"
HERE="$(cd "$(dirname "$0")" && pwd)"
"$HERE/ssh.sh" monolith bash -s <<REMOTE
set -euo pipefail
cd /opt/yeet
sed -i "s#^YEET_CHAIN=.*#YEET_CHAIN=$CHAIN#" backend.env
REMOTE
"$HERE/deploy.sh" "$TAG"
echo "switched to $CHAIN. Now: terraform apply (yeet_chain=$CHAIN) to update Pages env, then redeploy the frontend."
