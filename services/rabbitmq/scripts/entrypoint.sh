#!/bin/sh
set -e

# ═══════════════════════════════════════════════════════════════
# RabbitMQ Custom Entrypoint
# Dynamically generates definitions.json from .env variables
# ═══════════════════════════════════════════════════════════════

TEMPLATE="/etc/rabbitmq/definitions.json.template"
FINAL="/tmp/definitions.json"

escape_sed_replacement() {
    # Escape characters that are special in sed replacement strings.
    # We use "|" as delimiter below, so escape "\", "&", and "|".
    printf '%s' "$1" | sed 's/[\\&|]/\\&/g'
}

echo "🔧 Generating RabbitMQ definitions..."

if [ -f "$TEMPLATE" ]; then
    # Get credentials from environment
    USER="${RABBITMQ_DEFAULT_USER:-guest}"
    PASS="${RABBITMQ_DEFAULT_PASS:-guest}"
    ESCAPED_USER="$(escape_sed_replacement "$USER")"
    ESCAPED_PASS="$(escape_sed_replacement "$PASS")"

    # Create final definitions file
    # Replace placeholders safely even when values contain "/" or "&".
    sed -e "s|RABBITMQ_DEFAULT_USER|$ESCAPED_USER|g" \
        -e "s|RABBITMQ_DEFAULT_PASS|$ESCAPED_PASS|g" \
        "$TEMPLATE" > "$FINAL"

    echo "  ✅ Definitions generated successfully at $FINAL"
else
    echo "  ⚠️  No template found at $TEMPLATE — skipping generation"
fi

# Run the official entrypoint
echo "🚀 Starting RabbitMQ..."
exec docker-entrypoint.sh rabbitmq-server
