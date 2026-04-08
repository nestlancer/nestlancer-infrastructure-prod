<div align="center">

# Redis Pub/Sub Service Unit — Production

### Messaging engine · isolated 172.22.3.x network · ephemeral

[![Docker](https://img.shields.io/badge/Docker-Compose-2496ED?style=for-the-badge&logo=docker&logoColor=white)](https://docs.docker.com/compose/)
[![Linux](https://img.shields.io/badge/Host-Linux-FCC624?style=for-the-badge&logo=linux&logoColor=black)](https://kernel.org/)

<br/>

**Production-ready**, self-contained Redis pub/sub service optimized for message passing. No persistence — all data is ephemeral. This repository ships **production** configuration only (`ENV=prod` by default).

<br/>

[Quick Start](#quick-start) •
[Targets](#available-makefile-targets) •
[Variables](#environment-variables) •
[Key Differences](#key-differences-from-redis-cache) •
[Troubleshooting](#troubleshooting)

<br/>

---

</div>

<br/>

## Table of contents

<details>
<summary><b>Expand full outline</b></summary>

- [Quick Start](#quick-start)
- [Prerequisites](#prerequisites)
- [Available Makefile Targets](#available-makefile-targets)
- [Environment Variables](#environment-variables)
- [Key Differences from Redis Cache](#key-differences-from-redis-cache)
- [Port Mapping](#port-mapping)
- [Standalone VPS Deployment](#standalone-vps-deployment)
- [Troubleshooting](#troubleshooting)
- [Health & Readiness](#health--readiness)

</details>

---
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
