#!/bin/sh
set -e

# ═══════════════════════════════════════════════════════════════
# RabbitMQ Custom Entrypoint
# Dynamically generates definitions.json from .env variables
# ═══════════════════════════════════════════════════════════════

TEMPLATE="/etc/rabbitmq/definitions.json.template"
FINAL="/tmp/definitions.json"

echo "🔧 Generating RabbitMQ definitions..."

if [[ -f "$TEMPLATE" ]]; then
    # Get credentials from environment
    USER="${RABBITMQ_DEFAULT_USER:-guest}"
    PASS="${RABBITMQ_DEFAULT_PASS:-guest}"

    # Generate password hash using rabbitmqctl
    # We strip the first line ("Will hash password...") and take the hash
    echo "  - Hashing password for user: $USER"
    HASH=$(rabbitmqctl hash_password "$PASS" | tail -n 1)

    # Create final definitions file
    # Replace __USER__ with actual USER and __PASS_HASH__ with generated HASH
    sed -e "s/RABBITMQ_DEFAULT_USER/$USER/g" \
        -e "s/RABBITMQ_DEFAULT_PASS_HASH/$HASH/g" \
        "$TEMPLATE" > "$FINAL"

    echo "  ✅ Definitions generated successfully at $FINAL"
else
    echo "  ⚠️  No template found at $TEMPLATE — skipping generation"
fi

# Run the official entrypoint
echo "🚀 Starting RabbitMQ..."
exec docker-entrypoint.sh rabbitmq-server
