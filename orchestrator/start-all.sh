#!/usr/bin/env bash
set -euo pipefail

# ═══════════════════════════════════════════════════════════════
# START ALL — Start all services for PROD environment
# ═══════════════════════════════════════════════════════════════

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
ENV="prod"

export APP_ENV="$ENV"

echo "╔═══════════════════════════════════════════════════════╗"
echo "║   Starting ALL services for: ${ENV^^}"
echo "╚═══════════════════════════════════════════════════════╝"
echo ""

# Create networks first
"$ROOT_DIR/networks/create-networks.sh"
echo ""

# Start each service
SERVICES="postgres redis-cache redis-pubsub rabbitmq meilisearch clamav"

for service in $SERVICES; do
    echo "── Starting $service ($ENV) ──"
    make -C "$ROOT_DIR/services/$service" up
    echo ""
done

echo "╔═══════════════════════════════════════════════════════╗"
echo "║   ✅ All services for ${ENV^^} started                ║"
echo "╚═══════════════════════════════════════════════════════╝"
