# Meilisearch Service Unit (Prod Only)

Lightweight, lightning-fast search engine. Optimized for production with custom healthchecks and backup scripts.

## Quick Start

```bash
make up ENV=prod      # Start Meilisearch
make logs ENV=prod    # Tail logs
```

## Available Makefile Targets

| Target | Description |
|---|---|
| `make up ENV=prod` | Start Meilisearch |
| `make down ENV=prod` | Stop Meilisearch |
| `make restart ENV=prod` | Restart |
| `make logs ENV=prod` | Tail logs |
| `make status ENV=prod` | Show status + health |
| `make backup ENV=prod` | Trigger a dump via API (stored in /meili_data/dumps) |
| `make restore ENV=prod DUMP=<path>` | Restore from a dump (requires service restart) |
| `make clean ENV=prod` | Remove container + volume |

## Environment Variables

| Variable | Description | Default |
|---|---|---|
| `MEILI_MASTER_KEY` | Admin master key | *(none)* |
| `MEILI_ENV` | Meilisearch mode | `production` (required for this repo) |
| `MEILI_NO_ANALYTICS` | Bypass telemetry | `true` |

## Backup & Restore

Meilisearch uses **Dumps** for backups. 

- **Backup**: `make backup ENV=prod`. This triggers a background task. The script waits for completion and renames the dump to a standard format with a timestamp.
- **Restore**: `make restore ENV=prod DUMP=./path/to/dump.dump`. Meilisearch must be restarted to import a dump. The `make` command handles this orchestration.

## Port Mapping

| Environment | Host Port | Container Port |
|---|---|---|
| prod | `7700` | `7700` |

## Persistence

All data and dumps are stored in the `meili_data_prod` volume, mounted to `/meili_data` inside the container. Dumps are stored specifically in `/meili_data/dumps`.

## Healthcheck

The container uses a custom healthcheck (`healthcheck.sh`) that queries the `/health` endpoint of the Meilisearch API.
