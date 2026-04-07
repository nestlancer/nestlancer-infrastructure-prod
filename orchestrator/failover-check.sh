#!/usr/bin/env bash
set -euo pipefail

# ═══════════════════════════════════════════════════════════════
# FAILOVER CHECK — Within-environment isolation test (PROD)
# Tests that stopping one service doesn't affect others
# Usage: ./failover-check.sh
# ═══════════════════════════════════════════════════════════════

ENV="prod"
SERVICES=("postgres" "redis-cache" "redis-pubsub" "rabbitmq" "meilisearch" "clamav")
CONTAINERS=()
for svc in "${SERVICES[@]}"; do
    CONTAINERS+=("${svc}-${ENV}")
done
PASSED=0
FAILED=0
TOTAL=0

check_container_health() {
    local container="$1"
    local state
    state=$(docker inspect --format='{{.State.Status}}' "$container" 2>/dev/null || echo "not_found")
    [[ "$state" == "running" ]]
}

echo "╔═══════════════════════════════════════════════════════╗"
echo "║   WITHIN-ENV ISOLATION TEST — PROD                    ║"
echo "╚═══════════════════════════════════════════════════════╝"
echo ""

# For each service, stop it and check others are still running
for i in "${!SERVICES[@]}"; do
    SERVICE="${SERVICES[$i]}"
    CONTAINER="${CONTAINERS[$i]}"
    TOTAL=$((TOTAL + 1))

    echo "── Test: Stop $CONTAINER → others unaffected? ──"

    # Stop the service
    docker stop "$CONTAINER" >/dev/null 2>&1 || true
    sleep 2

    # Check remaining services
    ALL_OK=true
    for j in "${!CONTAINERS[@]}"; do
        if [[ "$j" != "$i" ]]; then
            if check_container_health "${CONTAINERS[$j]}"; then
                echo "  ✅ ${CONTAINERS[$j]} — still running"
            else
                echo "  ❌ ${CONTAINERS[$j]} — AFFECTED!"
                ALL_OK=false
            fi
        fi
    done

    if $ALL_OK; then
        echo "  ✅ PASSED — stopping $CONTAINER did not affect others"
        PASSED=$((PASSED + 1))
    else
        echo "  ❌ FAILED — stopping $CONTAINER affected other services"
        FAILED=$((FAILED + 1))
    fi

    # Restart the stopped service
    docker start "$CONTAINER" >/dev/null 2>&1 || true
    sleep 3
    echo ""
done

echo "╔═══════════════════════════════════════════════════════╗"
echo "║   RESULT: ${PASSED}/${TOTAL} passed, ${FAILED} failed"
if [[ $FAILED -eq 0 ]]; then
    echo "║   ✅ ALL WITHIN-ENV ISOLATION TESTS PASSED"
else
    echo "║   ❌ SOME TESTS FAILED"
fi
echo "╚═══════════════════════════════════════════════════════╝"

[[ $FAILED -eq 0 ]]
