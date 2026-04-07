# Redis Cache Service Unit

Self-contained Redis cache service with RDB+AOF persistence for maximum durability. This repository ships **production** configuration only (`ENV=prod` by default).

## Quick Start

```bash
make up              # Start Redis Cache (prod)
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
| `make up` | Start Redis Cache |
| `make down` | Stop Redis Cache |
| `make restart` | Restart |
| `make logs` | Tail container logs |
| `make shell` | Open redis-cli shell |
| `make status` | Show container status + health |
| `make build` | Build Docker image |
| `make rebuild` | Force rebuild (no cache) |
| `make clean` | Remove container + volumes |

## Environment Variables

| Variable | Description | Prod (`env/prod.env`) |
|---|---|---|
| `REDIS_PASSWORD` | Auth password | **Set a strong value** |
| `REDIS_MAXMEMORY` | Memory limit | e.g. `2gb` |
| `REDIS_LOGLEVEL` | Log verbosity | `warning` |

## Config Files (Base + Override)

```
config/
├── base/redis.conf     ← Shared: keepalive, timeout, clients
└── prod/redis.conf     ← Password, LFU, RDB, renamed commands
```

## Port Mapping

| Host | Container |
|---|---|
| **NONE** (internal only) | `6379` |

## Standalone VPS Deployment

```bash
scp -r redis-cache/ user@vps:/opt/redis-cache/
ssh user@vps "cd /opt/redis-cache && make up"
```

## Troubleshooting

| Issue | Solution |
|---|---|
| `NOAUTH` error | Set `REDIS_PASSWORD` in `env/prod.env` matching config |
| OOM killed | Increase `maxmemory` or container memory limit |
| Port conflict | Check `docker ps` for conflicting containers |

## Health & Readiness

The container provides a `wait-for-self.sh` script in `/usr/local/bin/scripts/` (or on the host in `scripts/`) that can be used by dependent services to wait until Redis is fully ready and responding to `PING`.

```bash
./scripts/wait-for-self.sh 30
```
