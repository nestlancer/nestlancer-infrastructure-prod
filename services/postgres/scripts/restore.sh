#!/usr/bin/env bash
set -euo pipefail

# ═══════════════════════════════════════════════════════════════
# PostgreSQL Restore Script — Restore from backup file
# Usage: ./restore.sh <backup_file>
# ═══════════════════════════════════════════════════════════════
 
if [[ "${PG_MODE:-master}" == "replica" ]]; then
    echo "❌ ERROR: Restore cannot be performed on a read-only replica."
    echo "   Please restore to the master database."
    exit 1
fi

BACKUP_FILE="${1:-}"
DB_NAME="${POSTGRES_DB:-app}"

if [[ -z "$BACKUP_FILE" ]]; then
    echo "❌ Usage: $0 <backup_file.sql.gz>"
    echo "   Available backups:"
    ls -la /var/lib/postgresql/backups/*.sql.gz 2>/dev/null || echo "   (none found)"
    exit 1
fi

if [[ ! -f "$BACKUP_FILE" ]]; then
    echo "❌ Backup file not found: $BACKUP_FILE"
    exit 1
fi

echo "═══════════════════════════════════════════════════"
echo "  PostgreSQL Restore"
echo "  Database: ${DB_NAME}"
echo "  Source: ${BACKUP_FILE}"
echo "═══════════════════════════════════════════════════"
echo ""
echo "⚠️  WARNING: This will overwrite the current database!"
echo "   Press Ctrl+C within 5 seconds to cancel..."
sleep 5

# Drop existing connections
psql -h localhost -U "${POSTGRES_USER:-postgres}" -d postgres <<-EOSQL
    SELECT pg_terminate_backend(pid)
    FROM pg_stat_activity
    WHERE datname = '${DB_NAME}' AND pid <> pg_backend_pid();
EOSQL

# Drop and recreate database
psql -h localhost -U "${POSTGRES_USER:-postgres}" -d postgres <<-EOSQL
    DROP DATABASE IF EXISTS ${DB_NAME};
    CREATE DATABASE ${DB_NAME};
EOSQL

# Restore
echo "🔄 Restoring from backup..."
gunzip -c "$BACKUP_FILE" | psql -h localhost -U "${POSTGRES_USER:-postgres}" -d "$DB_NAME"

echo "✅ Restore complete"
