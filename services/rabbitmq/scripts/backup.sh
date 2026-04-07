#!/bin/bash
set -e

# Configuration
BACKUP_DIR="/var/lib/rabbitmq/backups"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
ENV_TAG="${APP_ENV:-unknown}"
BACKUP_FILE="${BACKUP_DIR}/rabbitmq-${ENV_TAG}-definitions-${TIMESTAMP}.json"

echo "Starting RabbitMQ definitions backup..."

# Ensure backup directory exists
mkdir -p "${BACKUP_DIR}"

# Export definitions
# rabbitmqadmin is used to export metadata (users, vhosts, exchanges, queues, etc.)
if rabbitmqadmin -u "${RABBITMQ_DEFAULT_USER}" -p "${RABBITMQ_DEFAULT_PASS}" -H 127.0.0.1 export "${BACKUP_FILE}"; then
    echo "✅ Backup successful: ${BACKUP_FILE}"
    
    # Optional: Keep only last 7 backups
    ls -t ${BACKUP_DIR}/rabbitmq-${ENV_TAG}-definitions-*.json | tail -n +8 | xargs rm -f -- 2>/dev/null || true
else
    echo "❌ Backup failed!"
    exit 1
fi
