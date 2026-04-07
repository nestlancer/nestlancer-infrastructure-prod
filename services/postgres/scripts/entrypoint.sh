#!/usr/bin/env bash
set -euo pipefail

# ═══════════════════════════════════════════════════════════════
# PostgreSQL Custom Entrypoint — Config Merge Logic
# Merges base config + environment-specific override config
# then hands off to the original docker-entrypoint.sh
# ═══════════════════════════════════════════════════════════════

CONFIG_DIR="/etc/postgresql"
PG_DATA="${PGDATA:-/var/lib/postgresql/data}"
FINAL_CONFIG="${PG_DATA}/postgresql.conf"
FINAL_HBA="${PG_DATA}/pg_hba.conf"
PG_MODE="${PG_MODE:-master}"

# ── Generate self-signed SSL certs for prod if they don't exist ──
generate_ssl_certs() {
    local cert_file="${PG_DATA}/server.crt"
    local key_file="${PG_DATA}/server.key"

    if [[ "${APP_ENV:-prod}" == "prod" ]] && [[ ! -f "$cert_file" ]]; then
        echo "==> Generating self-signed SSL certificates for production..."
        openssl req -new -x509 -days 3650 -nodes \
            -out "$cert_file" \
            -keyout "$key_file" \
            -subj "/CN=postgres-prod" 2>/dev/null || true
        chmod 600 "$key_file"
        chown postgres:postgres "$cert_file" "$key_file" 2>/dev/null || true
        echo "==> SSL certificates generated"
    fi
}

# ── Merge configs on first init ──
merge_configs() {
    # Only merge if the data directory is being initialized
    # Check if base config files exist (they're mounted as volumes)
    if [[ -f "$CONFIG_DIR/base.conf" ]]; then
        echo "==> Merging PostgreSQL configuration..."
        echo "    Base: $CONFIG_DIR/base.conf"
        echo "    Override: $CONFIG_DIR/override.conf"

        # Create archive directory for WAL archiving (prod)
        mkdir -p "${PG_DATA}/../backups/archive" 2>/dev/null || true

        # Start with base, append overrides
        # The override values take precedence because PostgreSQL uses
        # the LAST occurrence of a directive
        cat "$CONFIG_DIR/base.conf" > "$FINAL_CONFIG"
        echo "" >> "$FINAL_CONFIG"
        echo "# ═══ ENVIRONMENT OVERRIDES (${APP_ENV:-prod}) ═══" >> "$FINAL_CONFIG"
        if [[ -f "$CONFIG_DIR/override.conf" ]]; then
            cat "$CONFIG_DIR/override.conf" >> "$FINAL_CONFIG"
        fi
        echo "==> PostgreSQL configuration merged"
    fi

    # Merge pg_hba.conf
    if [[ -f "$CONFIG_DIR/base_hba.conf" ]]; then
        echo "==> Merging pg_hba.conf..."
        # Use envsubst to expand ${REPLICATION_USER} and others
        envsubst < "$CONFIG_DIR/base_hba.conf" > "$FINAL_HBA"
        echo "" >> "$FINAL_HBA"
        echo "# ═══ ENVIRONMENT OVERRIDES (${APP_ENV:-prod}) ═══" >> "$FINAL_HBA"
        if [[ -f "$CONFIG_DIR/override_hba.conf" ]]; then
            # Expand overrides as well
            envsubst < "$CONFIG_DIR/override_hba.conf" >> "$FINAL_HBA"
        fi
        echo "==> pg_hba.conf merged and expanded"
    fi
}
 
# ── Handle Replica Initialization ──
init_replica() {
    echo "==> Initializing Read Replica..."
    
    if [[ -z "${POSTGRES_MASTER_HOST:-}" ]]; then
        echo "❌ ERROR: POSTGRES_MASTER_HOST must be set in replica mode."
        exit 1
    fi
 
    # Wait for master to be ready
    echo "==> Waiting for master ($POSTGRES_MASTER_HOST)..."
    until pg_isready -h "$POSTGRES_MASTER_HOST" -U "${REPLICATION_USER:-replicator}" -d postgres -q; do
        sleep 2
    done
    echo "==> Master is ready"
 
    # If data dir is empty, run pg_basebackup
    if [ ! -s "$PG_DATA/PG_VERSION" ]; then
        echo "==> Cloning data from master..."
        # Use pg_basebackup to clone the master
        # -R creates standby.signal and adds primary_conninfo to postgresql.auto.conf
        PGPASSWORD="${REPLICATION_PASSWORD:-changeme}" pg_basebackup \
            -h "$POSTGRES_MASTER_HOST" \
            -U "${REPLICATION_USER:-replicator}" \
            -D "$PG_DATA" \
            -R \
            -P \
            -v
            
        echo "==> Clone complete"
        chown -R postgres:postgres "$PG_DATA"
        chmod 700 "$PG_DATA"
    else
        echo "==> Data directory already initialized"
        # Ensure standby.signal exists for safety
        touch "$PG_DATA/standby.signal"
    fi
}

# ── Main ──

# Check for hook execution
if [[ "${1:-}" == "--hook" ]]; then
    merge_configs
    generate_ssl_certs
    exit 0
fi

echo "═══════════════════════════════════════════════════"
echo "  PostgreSQL Custom Entrypoint"
echo "  Environment: ${APP_ENV:-prod}"
echo "═══════════════════════════════════════════════════"

# Replica logic
if [[ "$PG_MODE" == "replica" ]]; then
    init_replica
fi

# Always merge if data exists (handles restarts/persistence)
if [ -s "$PG_DATA/PG_VERSION" ]; then
    echo "==> Data directory exists — merging configurations..."
    merge_configs
    generate_ssl_certs
fi

# Hand off to the original docker entrypoint
echo "==> Handoff to official docker-entrypoint.sh"
exec docker-entrypoint.sh "$@"
