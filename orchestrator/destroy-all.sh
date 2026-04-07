#!/usr/bin/env bash
set -euo pipefail

# ═══════════════════════════════════════════════════════════════
# DESTROY ALL — Nuclear option — remove everything for PROD
# Usage: ./destroy-all.sh
# ═══════════════════════════════════════════════════════════════

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
ENV="prod"

echo "╔═══════════════════════════════════════════════════════╗"
echo "║   ⚠️  NUCLEAR OPTION — Destroying PROD Environment    ║"
echo "║   All prod containers + all volumes + all networks    ║"
echo "╚═══════════════════════════════════════════════════════╝"
echo ""
echo "⏳ You have 5 seconds to cancel (Ctrl+C)..."
sleep 5

# Stop and remove all containers + volumes
SERVICES="postgres redis-cache redis-pubsub rabbitmq meilisearch clamav"
for service in $SERVICES; do
    echo "── Destroying $service ($ENV) ──"
    make -C "$ROOT_DIR/services/$service" clean 2>/dev/null || true
done

echo ""

# Destroy networks
"$ROOT_DIR/networks/destroy-networks.sh"

echo ""
echo "╔═══════════════════════════════════════════════════════╗"
echo "║   ✅ Prod environment destroyed                      ║"
echo "╚═══════════════════════════════════════════════════════╝"
