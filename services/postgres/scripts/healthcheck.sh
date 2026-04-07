#!/usr/bin/env bash
set -euo pipefail

# ═══════════════════════════════════════════════════════════════
# PostgreSQL Health Check
# Used by Docker HEALTHCHECK directive
# ═══════════════════════════════════════════════════════════════

pg_isready \
    -h localhost \
    -U "${POSTGRES_USER:-postgres}" \
    -d "${POSTGRES_DB:-postgres}" \
    -q

exit $?
