#!/usr/bin/env bash
set -euo pipefail

# ═══════════════════════════════════════════════════════════════
# LOGS — Aggregate or per-service logs for PROD
# Usage: ./logs.sh [service|all]
# Examples:
#   ./logs.sh                      # All prod containers (last 20 lines)
#   ./logs.sh postgres             # Tail prod postgres logs
#   ./logs.sh all                  # Tail all prod services
# ═══════════════════════════════════════════════════════════════

SERVICE="${1:-all-summary}"
ENV="prod"

case "$SERVICE" in
    all-summary)
        # Summary: primary + replica + app services (matches status.sh)
        echo "═══ Showing last 20 lines for ALL PROD containers ═══"
        CONTAINERS="postgres-prod postgres-replica-prod redis-cache-prod redis-pubsub-prod rabbitmq-prod meilisearch-prod clamav-prod"
        for c in $CONTAINERS; do
            if docker inspect "$c" >/dev/null 2>&1; then
                echo "═══ $c ═══"
                docker logs --tail=20 "$c" 2>&1 || true
                echo ""
            fi
        done
        ;;
    all)
        # Tail all services for prod
        echo "═══ Tailing ALL PROD services ═══"
        SVCS="postgres redis-cache redis-pubsub rabbitmq meilisearch clamav"
        for svc in $SVCS; do
            CONTAINER="${svc}-${ENV}"
            if docker inspect "$CONTAINER" >/dev/null 2>&1; then
                echo "═══ $CONTAINER ═══"
                docker logs --tail=50 -f "$CONTAINER" 2>&1 &
            fi
        done
        if docker inspect "postgres-replica-${ENV}" >/dev/null 2>&1; then
            echo "═══ postgres-replica-${ENV} ═══"
            docker logs --tail=50 -f "postgres-replica-${ENV}" 2>&1 &
        fi
        wait
        ;;
    *)
        # Specific service for prod
        CONTAINER="${SERVICE}-${ENV}"
        if docker inspect "$CONTAINER" >/dev/null 2>&1; then
            docker logs --tail=100 -f "$CONTAINER"
        else
            echo "❌ Container $CONTAINER not found."
            echo "   Usage: $0 [postgres|postgres-replica|redis-cache|redis-pubsub|rabbitmq|meilisearch|clamav|all]"
            exit 1
        fi
        ;;
esac
