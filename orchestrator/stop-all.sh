#!/usr/bin/env bash
set -euo pipefail

# ═══════════════════════════════════════════════════════════════
# STOP ALL — Stop all services for PROD environment
# ═══════════════════════════════════════════════════════════════

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
ENV="prod"

echo "╔═══════════════════════════════════════════════════════╗"
echo "║   Stopping ALL services for: ${ENV^^}"
echo "╚═══════════════════════════════════════════════════════╝"
echo ""

# Stop each service (reverse order)
SERVICES="clamav meilisearch rabbitmq redis-pubsub redis-cache postgres"

for service in $SERVICES; do
    echo "── Stopping $service ($ENV) ──"
    make -C "$ROOT_DIR/services/$service" down
    echo ""
done

echo "✅ All services for ${ENV^^} stopped"
