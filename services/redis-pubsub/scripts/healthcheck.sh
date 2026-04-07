#!/usr/bin/env bash
set -euo pipefail

# ═══════════════════════════════════════════════════════════════
# Redis Pub/Sub Health Check
# ═══════════════════════════════════════════════════════════════

if [[ -n "${REDIS_PASSWORD:-}" ]]; then
    redis-cli -a "$REDIS_PASSWORD" --no-auth-warning ping | grep -q PONG
else
    redis-cli ping | grep -q PONG
fi

exit $?
