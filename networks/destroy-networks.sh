#!/usr/bin/env bash
set -euo pipefail

# ═══════════════════════════════════════════════════════════════════
# DESTROY NETWORKS — Removes all networks for PROD
# Usage: ./destroy-networks.sh
# ═══════════════════════════════════════════════════════════════════

ENV="prod"

remove_network() {
    local name="$1"
    if docker network inspect "$name" >/dev/null 2>&1; then
        docker network rm "$name" >/dev/null 2>&1 || true
        echo "  🗑️  Removed network '$name'"
    else
        echo "  ⏭️  Network '$name' does not exist — skipping"
    fi
}

echo "═══════════════════════════════════════════════════"
echo "  Destroying networks for: ${ENV^^}"
echo "═══════════════════════════════════════════════════"

remove_network "gateway_${ENV}_network"
remove_network "pg_internal_${ENV}"
remove_network "rc_internal_${ENV}"
remove_network "rp_internal_${ENV}"
remove_network "rmq_internal_${ENV}"
remove_network "meili_internal_${ENV}"
remove_network "clam_internal_${ENV}"

echo ""
echo "✅ All networks for ${ENV^^} destroyed"
