#!/bin/bash
set -e

# Configuration
BACKUP_FILE=$1

if [ -z "${BACKUP_FILE}" ]; then
    echo "❌ Usage: $0 <backup_file_path>"
    exit 1
fi

if [ ! -f "${BACKUP_FILE}" ]; then
    echo "❌ Backup file not found: ${BACKUP_FILE}"
    exit 1
fi

echo "Starting RabbitMQ definitions restore from ${BACKUP_FILE}..."

# Import definitions
if rabbitmqadmin -u "${RABBITMQ_DEFAULT_USER}" -p "${RABBITMQ_DEFAULT_PASS}" import "${BACKUP_FILE}"; then
    echo "✅ Restore successful!"
else
    echo "❌ Restore failed!"
    exit 1
fi
