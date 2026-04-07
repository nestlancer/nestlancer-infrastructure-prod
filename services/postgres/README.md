# PostgreSQL Service Unit

Production-ready, self-contained PostgreSQL with automated configuration merging, multi-role initialization, SSL support, and optional read-replication. This repository ships **production** configuration only (`ENV=prod` by default).

## Quick Start

```bash
# 1. Start PostgreSQL (create required networks from repo root first if needed)
make up

# 2. Open interactive psql shell
make shell

# 3. Check health and status
make status
```

## Architecture Overview

This service is **fully self-contained**. The directory can be copied to a host and managed via the `Makefile` without external dependencies.

- **Production config**: `env/prod.env`, `config/prod/`.
- **Config engine**: “Base + override” for `postgresql.conf` and `pg_hba.conf`.
- **Infrastructure as code**: Networks, users, and tuning are version-controlled.

## Makefile Targets

| Target | Description |
|---|---|
| `make up` | Start primary (and replica if defined in compose) |
| `make down` | Stop service and preserve data |
| `make restart` | Restart containers |
| `make logs` | Tail service logs |
| `make shell` | `psql` as superuser |
| `make status` | Health and container stats |
| `make backup` | Timestamped, rotated backup |
| `make restore FILE=<path>` | Restore from `.sql.gz` |
| `make clean` | **Destructive**: remove container and volumes |

## Security and User Roles

Four roles are provisioned on first initialization:

| Role | Variable | Purpose |
|---|---|---|
| Superuser | `POSTGRES_USER` | Administration |
| App | `APP_DB_USER` | Application DDL/DML on app database |
| Read-only | `READONLY_DB_USER` | `SELECT` on public schema |
| Replicator | `REPLICATION_USER` | Streaming replication |

On first boot in production, self-signed TLS material is generated if missing, and authentication uses `scram-sha-256` as configured in `pg_hba`.

## Environment Variables

Secrets and tuning live in `env/prod.env`.

### When changes take effect

| Variable type | Effect |
|---|---|
| Core DB/user names | **First init only** |
| Passwords | **First init only** for roles; update roles manually if rotating after init |
| Operational (`HEALTHCHECK_INTERVAL`, `TZ`) | After `make restart` |

### Updating passwords after init

1. Preferred: `make shell`, then `ALTER ROLE ... WITH PASSWORD '...';`, then update `env/prod.env`.
2. Destructive: `make clean` then `make up` (wipes data).

## Configuration Merging

1. `config/base/postgresql.conf` loads first.
2. `config/prod/postgresql.conf` is appended and overrides base values.

Same pattern for `pg_hba.conf` via the entrypoint merge.

## Extensions

Enabled in the application database where applicable: `uuid-ossp`, `pg_trgm`, `hstore`, `pgcrypto`, `pg_stat_statements`.

## Read replication

Optional `postgres-replica` service clones via `pg_basebackup` on first run. In this prod stack, replicas are reached on the **internal Docker networks only** (no host port mapping for prod).

## Backup and restore

Backups live under `/var/lib/postgresql/backups` inside the container; rotation follows `BACKUP_RETENTION_DAYS`.

```bash
make backup
make restore FILE=./backups/postgres-prod-app_prod-20240324.sql.gz
```

## Directory layout

```text
.
├── compose/
├── config/       # base/ + prod/
├── docker/
├── env/          # prod.env
├── init/
├── scripts/
└── Makefile
```
