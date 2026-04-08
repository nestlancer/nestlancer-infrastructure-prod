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

# Wait for RabbitMQ to be ready
echo "Waiting for RabbitMQ to be ready..."
for i in {1..30}; do
    if rabbitmq-diagnostics -q check_running; then
        break
    fi
    echo "  Still waiting... ($i/30)"
    sleep 2
done

# Import definitions
if rabbitmqadmin -u "${RABBITMQ_DEFAULT_USER}" -p "${RABBITMQ_DEFAULT_PASS}" import "${BACKUP_FILE}"; then
    echo "✅ Restore successful!"
else
    echo "❌ Restore failed!"
    exit 1
fi
