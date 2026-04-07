#!/usr/bin/env bash
set -euo pipefail

# ═══════════════════════════════════════════════════════════════
# Wait for Redis Cache to be ready
# Usage: ./wait-for-self.sh [max_attempts]
# ═══════════════════════════════════════════════════════════════

MAX_ATTEMPTS="${1:-30}"
ATTEMPT=0

echo "⏳ Waiting for Redis Cache to be ready..."

while [ $ATTEMPT -lt "$MAX_ATTEMPTS" ]; do
    ATTEMPT=$((ATTEMPT + 1))
    if [[ -n "${REDIS_PASSWORD:-}" ]]; then
        READY=$(redis-cli -a "$REDIS_PASSWORD" --no-auth-warning ping 2>/dev/null || true)
    else
        READY=$(redis-cli ping 2>/dev/null || true)
    fi

    if [[ "$READY" == "PONG" ]]; then
        echo "✅ Redis Cache is ready (attempt ${ATTEMPT}/${MAX_ATTEMPTS})"
        exit 0
    fi
    echo "  Attempt ${ATTEMPT}/${MAX_ATTEMPTS} — not ready yet..."
    sleep 2
done

echo "❌ Redis Cache did not become ready after ${MAX_ATTEMPTS} attempts"
exit 1
