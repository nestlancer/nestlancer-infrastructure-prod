#!/usr/bin/env bash
set -euo pipefail

# ═══════════════════════════════════════════════════════════════
# 02-create-users.sh — Idempotent user/role creation
# Creates app user (read/write) and readonly user
# ═══════════════════════════════════════════════════════════════

echo "==> [02] Creating users and roles..."

APP_USER="${APP_DB_USER:-app_user}"
APP_PASS="${APP_DB_PASSWORD:-changeme}"
RO_USER="${READONLY_DB_USER:-readonly_user}"
RO_PASS="${READONLY_DB_PASSWORD:-changeme}"
REP_USER="${REPLICATION_USER:-replicator}"
REP_PASS="${REPLICATION_PASSWORD:-changeme}"
DB_NAME="${APP_DB_NAME:-app}"

psql -v ON_ERROR_STOP=0 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    -- Create app user (idempotent)
    DO \$\$
    BEGIN
        IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '${APP_USER}') THEN
            CREATE ROLE ${APP_USER} WITH LOGIN PASSWORD '${APP_PASS}';
        END IF;
    END
    \$\$;

    -- Grant privileges to app user
    GRANT CONNECT ON DATABASE ${DB_NAME} TO ${APP_USER};

    -- Create readonly user (idempotent)
    DO \$\$
    BEGIN
        IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '${RO_USER}') THEN
            CREATE ROLE ${RO_USER} WITH LOGIN PASSWORD '${RO_PASS}';
        END IF;
    END
    \$\$;

    -- Grant readonly privileges
    GRANT CONNECT ON DATABASE ${DB_NAME} TO ${RO_USER};
 
    -- Create replication user (idempotent, needs REPLICATION attribute)
    DO \$\$
    BEGIN
        IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '${REP_USER}') THEN
            CREATE ROLE ${REP_USER} WITH REPLICATION LOGIN PASSWORD '${REP_PASS}';
        END IF;
    END
    \$\$;
EOSQL

# Grant schema-level privileges (must connect to the target database)
psql -v ON_ERROR_STOP=0 --username "$POSTGRES_USER" --dbname "$DB_NAME" <<-EOSQL
    -- App user: full access to public schema
    GRANT USAGE, CREATE ON SCHEMA public TO ${APP_USER};
    GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO ${APP_USER};
    GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO ${APP_USER};
    ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO ${APP_USER};
    ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO ${APP_USER};

    -- Readonly user: read-only access
    GRANT USAGE ON SCHEMA public TO ${RO_USER};
    GRANT SELECT ON ALL TABLES IN SCHEMA public TO ${RO_USER};
    ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO ${RO_USER};
EOSQL

echo "==> [02] Users and roles created"
