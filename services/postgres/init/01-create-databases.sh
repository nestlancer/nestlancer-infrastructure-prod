#!/usr/bin/env bash
set -euo pipefail

# ═══════════════════════════════════════════════════════════════
# 01-create-databases.sh — Idempotent database creation
# Runs as part of PostgreSQL init (docker-entrypoint-initdb.d)
# ═══════════════════════════════════════════════════════════════

echo "==> [01] Creating databases..."

# The main database ($POSTGRES_DB) is created automatically by the
# official postgres image. Create additional databases here.

DB_NAME="${APP_DB_NAME:-app}"

# Idempotent: only create if it doesn't exist
psql -v ON_ERROR_STOP=0 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    SELECT 'CREATE DATABASE ${DB_NAME}'
    WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '${DB_NAME}')\gexec
EOSQL

echo "==> [01] Database creation complete"
