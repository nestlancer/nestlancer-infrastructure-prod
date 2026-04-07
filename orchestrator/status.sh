#!/usr/bin/env bash
set -euo pipefail

# ═══════════════════════════════════════════════════════════════
# STATUS — Production Environment status dashboard
# ═══════════════════════════════════════════════════════════════
PROD_CONTAINERS=(
    "postgres-prod"
    "postgres-replica-prod"
    "redis-cache-prod"
    "redis-pubsub-prod"
    "rabbitmq-prod"
    "meilisearch-prod"
    "clamav-prod"
)

echo "╔═══════════════════════════════════════════════════════════════════════════╗"
echo "║                  INFRASTRUCTURE STATUS DASHBOARD (PROD)                  ║"
echo "╠══════════════════════╦══════════╦══════════╦════════════╦════════════════╣"
printf "║ %-20s ║ %-8s ║ %-8s ║ %-10s ║ %-14s ║\n" "CONTAINER" "STATE" "HEALTH" "PORTS" "UPTIME"
echo "╠══════════════════════╬══════════╬══════════╬════════════╬════════════════╣"

for container in "${PROD_CONTAINERS[@]}"; do
    if docker inspect "$container" >/dev/null 2>&1; then
        STATE=$(docker inspect --format='{{.State.Status}}' "$container" 2>/dev/null)
        HEALTH=$(docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}N/A{{end}}' "$container" 2>/dev/null)
        PORTS=$(docker port "$container" 2>/dev/null | head -1 | sed 's/.*://;s/ //g' || echo "—")
        STARTED=$(docker inspect --format='{{.State.StartedAt}}' "$container" 2>/dev/null)

        # Calculate uptime
        if [[ "$STATE" == "running" ]]; then
            START_EPOCH=$(date -d "$STARTED" +%s 2>/dev/null || echo "0")
            if [[ "$START_EPOCH" != "0" ]]; then
                NOW_EPOCH=$(date +%s)
                DIFF=$((NOW_EPOCH - START_EPOCH))
                if [[ $DIFF -lt 60 ]]; then UPTIME="${DIFF}s"
                elif [[ $DIFF -lt 3600 ]]; then UPTIME="$((DIFF / 60))m"
                else UPTIME="$((DIFF / 3600))h $((DIFF % 3600 / 60))m"
                fi
            else
                UPTIME="—"
            fi
        else
            UPTIME="—"
        fi

        # State Icon
        case "$STATE" in
            running) STATE_ICON="✅ run" ;;
            exited)  STATE_ICON="❌ exit" ;;
            *)       STATE_ICON="⚠️  $STATE" ;;
        esac

        # Health Icon
        case "$HEALTH" in
            healthy)   HEALTH_ICON="✅ ok" ;;
            unhealthy) HEALTH_ICON="❌ bad" ;;
            starting)  HEALTH_ICON="⏳ init" ;;
            *)         HEALTH_ICON="— N/A" ;;
        esac

        printf "║ %-20s ║ %-8s ║ %-8s ║ %-10s ║ %-14s ║\n" \
            "$container" "$STATE_ICON" "$HEALTH_ICON" "$PORTS" "$UPTIME"
    else
        printf "║ %-20s ║ %-8s ║ %-8s ║ %-10s ║ %-14s ║\n" \
            "$container" "❌ none" "—" "—" "—"
    fi
done

echo "╚══════════════════════╩══════════╩══════════╩════════════╩════════════════╝"
