#!/usr/bin/env bash
set -euo pipefail

# ═══════════════════════════════════════════════════════════════
# 03-extensions.sh — Enable required PostgreSQL extensions
# Idempotent: CREATE EXTENSION IF NOT EXISTS
# ═══════════════════════════════════════════════════════════════

echo "==> [03] Enabling extensions..."

DB_NAME="${APP_DB_NAME:-app}"

# Extensions to enable
EXTENSIONS=(
    "uuid-ossp"
    "pg_trgm"
    "hstore"
    "pgcrypto"
    "pg_stat_statements"
)

for ext in "${EXTENSIONS[@]}"; do
    psql -v ON_ERROR_STOP=0 --username "$POSTGRES_USER" --dbname "$DB_NAME" <<-EOSQL
        CREATE EXTENSION IF NOT EXISTS "${ext}";
EOSQL
    echo "  ✅ Extension '${ext}' enabled"
done

echo "==> [03] All extensions enabled"
