# Redis Pub/Sub Service Unit

Self-contained Redis pub/sub service optimized for message passing. No persistence — all data is ephemeral. This repository ships **production** configuration only (`ENV=prod` by default).

## Quick Start

```bash
make up              # Start Redis Pub/Sub (prod)
make shell           # Open redis-cli
make logs            # Tail logs
```

## Prerequisites

- Docker Engine 24+
- Docker Compose V2+
- `make` utility

## Available Makefile Targets

| Target | Description |
|---|---|
| `make up` | Start Redis Pub/Sub |
| `make down` | Stop |
| `make restart` | Restart |
| `make logs` | Tail logs |
| `make shell` | Open redis-cli |
| `make status` | Show status + health |
| `make build` | Build Docker image |
| `make rebuild` | Force rebuild |
| `make clean` | Remove container |

## Environment Variables

| Variable | Prod (`env/prod.env`) |
|---|---|
| `REDIS_PASSWORD` | **Set a strong value** |
| `REDIS_MAXMEMORY` | e.g. `512mb` |
| `REDIS_LOGLEVEL` | `warning` |

## Key Differences from Redis Cache

- **No persistence** — all data is ephemeral
- **Keyspace notifications** — `notify-keyspace-events KEA` enabled
- **Eviction** — `noeviction` policy (never drops messages)
- **High hz** — 100 (faster processing of pub/sub events)

## Port Mapping

| Host | Container |
|---|---|
| **NONE** (internal only) | `6379` |

## Standalone VPS Deployment

```bash
scp -r redis-pubsub/ user@vps:/opt/redis-pubsub/
ssh user@vps "cd /opt/redis-pubsub && make up"
```

## Troubleshooting

| Issue | Solution |
|---|---|
| Messages not received | Check subscriber connection and keyspace events config |
| `NOAUTH` error | Set `REDIS_PASSWORD` in `env/prod.env` |

## Health & Readiness

The container includes a `wait-for-self.sh` script to help orchestrate startup for services that depend on Pub/Sub availability.

Usage: `./scripts/wait-for-self.sh [max_attempts]`
