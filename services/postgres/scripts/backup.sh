#!/usr/bin/env bash
set -euo pipefail

# ═══════════════════════════════════════════════════════════════
# PostgreSQL Backup Script — pg_dump with rotation
# Usage: ./backup.sh [backup_dir]
# ═══════════════════════════════════════════════════════════════
 
if [[ "${PG_MODE:-master}" == "replica" ]]; then
    echo "❌ ERROR: Backup cannot be performed on a read-only replica."
    echo "   Please run backups on the master database."
    exit 1
fi

BACKUP_DIR="${1:-/var/lib/postgresql/backups}"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
DB_NAME="${POSTGRES_DB:-app}"
ENV_TAG="${APP_ENV:-unknown}"
BACKUP_FILE="${BACKUP_DIR}/postgres-${ENV_TAG}-${DB_NAME}-${TIMESTAMP}.sql.gz"
RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-7}"

echo "═══════════════════════════════════════════════════"
echo "  PostgreSQL Backup"
echo "  Database: ${DB_NAME}"
echo "  Target: ${BACKUP_FILE}"
echo "═══════════════════════════════════════════════════"

# Ensure backup directory exists
mkdir -p "$BACKUP_DIR"

# Perform backup
pg_dump \
    -h localhost \
    -U "${POSTGRES_USER:-postgres}" \
    -d "$DB_NAME" \
    --format=plain \
    --no-owner \
    --no-privileges \
    | gzip > "$BACKUP_FILE"

# Verify backup was created
if [[ -f "$BACKUP_FILE" ]] && [[ -s "$BACKUP_FILE" ]]; then
    SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
    echo "✅ Backup complete: ${BACKUP_FILE} (${SIZE})"
else
    echo "❌ Backup failed — file is empty or missing"
    exit 1
fi

# Rotate old backups
echo "🔄 Rotating backups older than ${RETENTION_DAYS} days..."
find "$BACKUP_DIR" -name "postgres-${ENV_TAG}-${DB_NAME}-*.sql.gz" -mtime +"$RETENTION_DAYS" -delete
REMAINING=$(find "$BACKUP_DIR" -name "postgres-${ENV_TAG}-${DB_NAME}-*.sql.gz" | wc -l)
echo "📁 ${REMAINING} backup(s) retained"
