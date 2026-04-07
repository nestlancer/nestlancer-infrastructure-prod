#!/usr/bin/env bash
set -euo pipefail

# ═══════════════════════════════════════════════════════════════
# RESTART SERVICE — Restart a single production container
# Usage: ./restart-service.sh <service>
# ═══════════════════════════════════════════════════════════════

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
SERVICE="${1:-}"
ENV="prod"

if [[ -z "$SERVICE" ]]; then
    echo "❌ Usage: $0 <postgres|redis-cache|redis-pubsub|rabbitmq|meilisearch|clamav>"
    exit 1
fi

if [[ ! -d "$ROOT_DIR/services/$SERVICE" ]]; then
    echo "❌ Invalid service: $SERVICE"
    echo "   Available: $(ls "$ROOT_DIR/services" | xargs)"
    exit 1
fi

echo "🔄 Restarting $SERVICE ($ENV)..."
make -C "$ROOT_DIR/services/$SERVICE" restart
echo "✅ $SERVICE ($ENV) restarted"
