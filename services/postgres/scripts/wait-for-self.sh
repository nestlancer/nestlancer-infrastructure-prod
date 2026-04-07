#!/usr/bin/env bash
set -euo pipefail

# ═══════════════════════════════════════════════════════════════
# Wait for PostgreSQL to be ready
# Usage: ./wait-for-self.sh [max_attempts]
# ═══════════════════════════════════════════════════════════════

MAX_ATTEMPTS="${1:-30}"
ATTEMPT=0

echo "⏳ Waiting for PostgreSQL to be ready..."

while [ $ATTEMPT -lt "$MAX_ATTEMPTS" ]; do
    ATTEMPT=$((ATTEMPT + 1))
    if pg_isready -h localhost -U "${POSTGRES_USER:-postgres}" -q 2>/dev/null; then
        echo "✅ PostgreSQL is ready (attempt ${ATTEMPT}/${MAX_ATTEMPTS})"
        exit 0
    fi
    echo "  Attempt ${ATTEMPT}/${MAX_ATTEMPTS} — not ready yet..."
    sleep 2
done

echo "❌ PostgreSQL did not become ready after ${MAX_ATTEMPTS} attempts"
exit 1
