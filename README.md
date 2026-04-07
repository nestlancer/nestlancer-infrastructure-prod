<div align="center">

# Nestlancer Infrastructure — Production

### Seven hardened containers · isolated `172.22.x.x` networks · zero host ports · Tailscale + B2 backups

[![Docker](https://img.shields.io/badge/Docker-Compose-2496ED?style=for-the-badge&logo=docker&logoColor=white)](https://docs.docker.com/compose/)
[![Linux](https://img.shields.io/badge/Host-Linux-FCC624?style=for-the-badge&logo=linux&logoColor=black)](https://kernel.org/)
[![Tailscale](https://img.shields.io/badge/Access-Tailscale-000000?style=for-the-badge)](https://tailscale.com/)
[![Architecture](https://img.shields.io/badge/Spec-architecture--prod.md-3498DB?style=for-the-badge)](./architecture-prod.md)

<br/>

**Production-only repo:** PostgreSQL primary + replica, Redis cache, Redis pub/sub, RabbitMQ, Meilisearch, and ClamAV — orchestrated with **Make**, **Bash**, and **Docker Compose** (base + `docker-compose.prod.yml`).

<br/>

[Overview](#1-overview--setup) •
[Operations](#2-daily-operations) •
[Backups](#3-backup--restore) •
[Monitoring](#4-monitoring--observability) •
[Tailscale & host](#5-tailscale--host-tuning) •
[Reference](#6-reference-prod-only) •
[Troubleshooting](#7-troubleshooting) •
[Security](#8-security-checklist-production)

<br/>

---

</div>

<br/>

## Table of contents

<details>
<summary><b>Expand full outline</b></summary>

### Part I — Overview & setup
1. [Overview & setup](#1-overview--setup)
   - [Prerequisites](#11-prerequisites)
   - [Architecture](#12-architecture)
   - [Design principles](#13-design-principles)
   - [Directory structure](#14-directory-structure)
   - [Quick start](#15-quick-start)
2. [Daily operations](#2-daily-operations)
   - [Root Makefile](#21-root-makefile--primary-interface)
   - [Service-level commands](#22-service-level-commands)
   - [Orchestrator scripts](#23-orchestrator-scripts)
   - [Network management](#24-network-management)
   - [Isolation test](#25-isolation-test)
3. [Backup & restore](#3-backup--restore)
4. [Monitoring & observability](#4-monitoring--observability)
5. [Tailscale & host tuning](#5-tailscale--host-tuning)
6. [Reference (prod only)](#6-reference-prod-only)
7. [Troubleshooting](#7-troubleshooting)
8. [Security checklist (production)](#8-security-checklist-production)

</details>

---

# 1. Overview & setup

> **Scope:** This repository defines **one** environment: **production**. There are no dev/test compose targets, Mailpit, or MinIO here. Full diagrams, limits, and DR detail: **[architecture-prod.md](./architecture-prod.md)**.

---

## 1.1 Prerequisites

| Requirement | Minimum | Check |
|:------------|:--------|:------|
| Docker Engine | 24+ | `docker --version` |
| Docker Compose | v2+ | `docker compose version` |
| GNU Make | 4+ | `make --version` |
| Bash | 4+ | `bash --version` |

Run all examples from the **`nestlancer-infrastructure-prod/`** root unless noted otherwise.

---

## 1.2 Architecture

Single Docker host: **seven** containers on **`172.22.x.x`**, gateway **`172.22.0.0/24`**, each service also attached to its own **internal `/28`**. **No host port mappings** — reach services via Tailscale (or other private routing) to advertised subnets, or from the host with `docker exec`.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         PRODUCTION DOCKER HOST                               │
│                                                                             │
│   ┌─── PROD (172.22.x.x) ─────────────────────────────────────────────────┐ │
│   │  postgres-prod          redis-cache-prod        rabbitmq-prod          │ │
│   │  postgres-replica-prod  redis-pubsub-prod       meilisearch-prod       │ │
│   │                                            clamav-prod                  │ │
│   │  Gateway: gateway_prod_network  +  per-service internal networks        │ │
│   │  Host ports: NONE — Tailscale / internal access only                      │ │
│   └─────────────────────────────────────────────────────────────────────────┘ │
│                                                                             │
│   Data root (typical): /root/Desktop/docker-infra-data/prod/<service>/       │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 1.3 Design principles

| Principle | Implementation |
|:----------|:---------------|
| **No public attach surface** | Prod compose overrides omit `ports:`; access via VPN/subnets or `docker exec`. |
| **Service isolation** | Separate internal bridge per stack (`pg_internal_prod`, `rc_internal_prod`, …). |
| **Static addressing** | `ipv4_address` in prod compose for stable connection strings (see §6). |
| **Base + override** | `compose/docker-compose.yml` merged with `docker-compose.prod.yml` + `env/prod.env`. |
| **Idempotent networks** | `networks/create-networks.sh` and per-service `network-create` targets skip existing nets. |
| **Operational symmetry** | Each `services/<name>/` is self-contained (Dockerfile, compose, config, Makefile). |

---

## 1.4 Directory structure

```
nestlancer-infrastructure-prod/
├── Makefile                    ← Root interface (prod only)
├── architecture-prod.md        ← Full system specification
├── README.md                   ← This document
├── networks/
│   ├── create-networks.sh
│   ├── destroy-networks.sh
│   ├── list-networks.sh
│   └── network-config.yml
├── orchestrator/
│   ├── start-all.sh / stop-all.sh / status.sh / logs.sh
│   ├── restart-service.sh
│   ├── failover-check.sh
│   └── destroy-all.sh
├── scripts/
│   ├── backup-all.sh / cloud-sync.sh / monitor-containers.sh
│   ├── optimize-host.sh / tailscale-setup.sh
│   ├── cron.md / rclone.md
│   └── .cloud-sync.env         ← gitignored (see rclone.md)
└── services/
    ├── postgres/
    ├── redis-cache/
    ├── redis-pubsub/
    ├── rabbitmq/
    ├── meilisearch/
    └── clamav/
```

Each service directory typically contains `docker/`, `compose/`, `config/`, `env/prod.env`, `scripts/`, `Makefile`, and `README.md`.

---

## 1.5 Quick start

```bash
cd nestlancer-infrastructure-prod

# 1. Fill secrets: services/*/env/prod.env (never commit; chmod 600)

# 2. Create prod networks
make networks-create

# 3. (Recommended on the Docker host)
sudo ./scripts/optimize-host.sh
sudo ./scripts/tailscale-setup.sh
# Approve advertised routes in https://login.tailscale.com/admin/machines

# 4. Start the full stack (postgres → redis* → rabbitmq → meilisearch → clamav)
make env-up

# 5. Verify
make env-status
```

**After Tailscale routes are approved**, examples (see [architecture-prod.md](./architecture-prod.md) for exact DB names and users):

```bash
psql -h 172.22.1.2 -p 5432 -U nl_platform_app -d nl_platform_prod
redis-cli -h 172.22.2.2 -p 6379 -a "$REDIS_PASSWORD"
# RabbitMQ management (browser)
# http://172.22.4.2:15672
```

---

# 2. Daily operations

---

## 2.1 Root Makefile — primary interface

| Command | Description |
|:--------|:------------|
| `make help` | List targets with descriptions |
| `make env-up` | Start all prod services (`orchestrator/start-all.sh`) |
| `make env-down` | Stop all prod services |
| `make env-restart` | Stop then start all |
| `make env-status` | Prod status dashboard |
| `make env-logs` | Aggregate logs (`orchestrator/logs.sh all`) |
| `make networks-create` | Create gateway + internal prod networks |
| `make networks-destroy` | Destroy prod networks (impact: connectivity) |
| `make networks-list` | List project networks |
| `make isolation-test` | Run `orchestrator/failover-check.sh` |
| `make clean` | Remove containers + volumes **per service** (destructive) |
| `make prune` | `docker system prune` + volume prune |

### Per-service (root delegates to `services/<name>/`)

| Area | Examples |
|:-----|:---------|
| **PostgreSQL** | `postgres-up`, `postgres-down`, `postgres-restart`, `postgres-logs`, `postgres-shell`, `postgres-status`, `postgres-backup`, `postgres-restore FILE=/path/to/backup.sql.gz` |
| **Redis cache** | `redis-cache-up`, `redis-cache-down`, `redis-cache-restart`, `redis-cache-logs`, `redis-cache-shell`, `redis-cache-status` |
| **Redis pub/sub** | `redis-pubsub-up`, … `redis-pubsub-shell`, … |
| **RabbitMQ** | `rabbitmq-up`, … `rabbitmq-backup`, `rabbitmq-restore FILE=/path/to/backup.json` |
| **Meilisearch** | `meilisearch-up`, `meilisearch-down`, `meilisearch-restart`, `meilisearch-logs`, `meilisearch-status` |
| **ClamAV** | `clamav-up`, `clamav-down`, `clamav-restart`, `clamav-logs`, `clamav-status` |

> **Meilisearch backups** are implemented on the **service** Makefile: `make -C services/meilisearch backup` (and `restore` with `FILE=`). See that Makefile for usage.

---

## 2.2 Service-level commands

From a service directory, targets are **prod-only** (`ENV := prod` in each Makefile):

```bash
cd services/postgres
make help
make up      # start primary + replica
make logs
make shell   # psql
```

Same pattern for `redis-cache`, `redis-pubsub`, `rabbitmq`, `meilisearch`, `clamav`.

---

## 2.3 Orchestrator scripts

Located in `orchestrator/`.

| Script | Purpose |
|:-------|:--------|
| `start-all.sh` | Creates networks, starts services in dependency order |
| `stop-all.sh` | Stops all prod containers |
| `status.sh` | Dashboard (state, health, ports, uptime) |
| `logs.sh` | `all-summary` default; `./logs.sh all` tails all; `./logs.sh postgres` per service |
| `restart-service.sh` | `./restart-service.sh postgres` (or `redis-cache`, `rabbitmq`, …) |
| `failover-check.sh` | Isolation / failover checks (`make isolation-test`) |
| `destroy-all.sh` | Nuclear teardown (use with care) |

---

## 2.4 Network management

```bash
make networks-create
make networks-list
./networks/destroy-networks.sh    # or: make networks-destroy
```

Creates are safe to repeat; existing networks are skipped.

---

## 2.5 Isolation test

```bash
make isolation-test
# or: ./orchestrator/failover-check.sh
```

---

# 3. Backup & restore

| Service | Method | Automation |
|:--------|:-------|:-----------|
| **PostgreSQL** | `pg_dump` → `.sql.gz` | `scripts/backup-all.sh prod` (cron — see `scripts/cron.md`) |
| **RabbitMQ** | Definitions export → `.json` | Same |
| **Meilisearch** | Dump API → `.dump` | Same + `make -C services/meilisearch backup` |
| **Cloud copy** | `rclone` → Backblaze B2 | `scripts/cloud-sync.sh` (`scripts/rclone.md`, `scripts/.cloud-sync.env`) |

**Examples:**

```bash
make postgres-backup
make postgres-restore FILE=/path/to/backup.sql.gz

make rabbitmq-backup
make rabbitmq-restore FILE=/path/to/definitions.json

make -C services/meilisearch backup

cd scripts && ./backup-all.sh prod
cd scripts && ./cloud-sync.sh --dry-run && ./cloud-sync.sh --status
```

Retention and bucket layout are documented in **[architecture-prod.md](./architecture-prod.md)** (§12).

---

# 4. Monitoring & observability

| Task | Command |
|:-----|:--------|
| **Dashboard** | `make env-status` |
| **Logs** | `make env-logs` / `make postgres-logs` / `./orchestrator/logs.sh rabbitmq` |
| **Resource report** | `./scripts/monitor-containers.sh --duration 60 --env prod` → `reports/container-resources-prod-*.md` |
| **Health JSON** | `docker inspect --format='{{json .State.Health}}' postgres-prod \| jq` |
| **Run healthcheck** | `docker exec postgres-prod /usr/local/bin/healthcheck.sh` |

Webhook notifications for backup/sync outcomes are described in **architecture-prod.md** §13.

---

# 5. Tailscale & host tuning

### Tailscale subnet routing

On the Docker host, prefer the bundled script (detects nets, forwarding, firewall):

```bash
sudo ./scripts/tailscale-setup.sh
```

Approve **all** advertised prod routes in the admin console, for example:

`172.22.0.0/24`, `172.22.1.0/28`, `172.22.2.0/28`, `172.22.3.0/28`, `172.22.4.0/28`, `172.22.5.0/28`, `172.22.6.0/28`

### Host kernel optimization

```bash
sudo ./scripts/optimize-host.sh
```

Tunables and persistence path are described in **architecture-prod.md** (aligned with swappiness, `somaxconn`, THP, etc.).

---

# 6. Reference (prod only)

## 6.1 Container names

| Role | Container |
|:-----|:----------|
| PostgreSQL primary | `postgres-prod` |
| PostgreSQL replica | `postgres-replica-prod` |
| Redis cache | `redis-cache-prod` |
| Redis pub/sub | `redis-pubsub-prod` |
| RabbitMQ | `rabbitmq-prod` |
| Meilisearch | `meilisearch-prod` |
| ClamAV | `clamav-prod` |

## 6.2 Static IPs (gateway attachment)

| Container | Internal network | IPv4 |
|:----------|:-----------------|:-----|
| `postgres-prod` | `pg_internal_prod` | `172.22.1.2` |
| `postgres-replica-prod` | `pg_internal_prod` | `172.22.1.3` |
| `redis-cache-prod` | `rc_internal_prod` | `172.22.2.2` |
| `redis-pubsub-prod` | `rp_internal_prod` | `172.22.3.2` |
| `rabbitmq-prod` | `rmq_internal_prod` | `172.22.4.2` |
| `meilisearch-prod` | `meili_internal_prod` | `172.22.5.2` |
| `clamav-prod` | `clam_internal_prod` | `172.22.6.2` |

## 6.3 Prod networks

| Network | Subnet |
|:--------|:-------|
| `gateway_prod_network` | `172.22.0.0/24` |
| `pg_internal_prod` | `172.22.1.0/28` |
| `rc_internal_prod` | `172.22.2.0/28` |
| `rp_internal_prod` | `172.22.3.0/28` |
| `rmq_internal_prod` | `172.22.4.0/28` |
| `meili_internal_prod` | `172.22.5.0/28` |
| `clam_internal_prod` | `172.22.6.0/28` |

## 6.4 Host ports

| Service | Host publish |
|:--------|:-------------|
| All prod services | **None** |

Use Tailscale (or host `docker exec`) for access.

## 6.5 Compose project names (debugging)

| Service | Compose `-p` |
|:--------|:-------------|
| PostgreSQL | `pg-prod` |
| Redis cache | `rc-prod` |
| Redis pub/sub | `rp-prod` |
| RabbitMQ | `rmq-prod` |
| Meilisearch | `meili-prod` |
| ClamAV | `clamav-prod` |

## 6.6 Raw `docker compose` (PostgreSQL example)

```bash
cd services/postgres
docker compose \
  -f compose/docker-compose.yml \
  -f compose/docker-compose.prod.yml \
  --env-file env/prod.env \
  -p pg-prod \
  up -d --build

docker compose -p pg-prod ps
docker compose -p pg-prod config
```

Mirror the same pattern for other services (`rc-prod`, `rmq-prod`, …).

## 6.7 Useful Docker commands (prod)

```bash
docker ps --filter "name=prod"
docker stats postgres-prod redis-cache-prod rabbitmq-prod --no-stream
docker logs -f --tail=100 postgres-prod
docker exec -it postgres-prod psql -U nl_infra_admin -d nl_platform_prod
```

---

# 7. Troubleshooting

| Symptom | Likely cause | What to try |
|:--------|:-------------|:------------|
| Cannot connect from laptop | Tailscale routes not approved or wrong IP | `tailscale status`; confirm §6.2 addresses; re-run `tailscale-setup.sh` |
| `env-up` / `up` fails on network | Missing bridge or stale state | `make networks-list`; recreate only if safe |
| Health stays **starting** | Long init (ClamAV DB), or wrong secrets | `docker logs <container>`; wait for ClamAV; verify `prod.env` |
| PostgreSQL auth errors | Password / `pg_hba` mismatch | Compare `env/prod.env` with `config/prod/pg_hba.conf` |
| Redis `NOAUTH` | Password not passed | Use `-a` / match `redis.conf` `requirepass` |
| Disk full | Backups + Docker logs | Retention per architecture §12; `docker system df`; prune old `pg_backups` |
| Compose changes ignored | Data dir already initialized | For Postgres, many settings need volume recreate (know the data loss risk) |

---

# 8. Security checklist (production)

### Before go-live

- [ ] Strong unique secrets in every `services/*/env/prod.env` (rotation policy per **architecture-prod.md** §6.4)
- [ ] **No** host `ports:` in prod overrides for any service
- [ ] Hardening present where applicable: `read_only`, `tmpfs`, `cap_drop` / `cap_add`, `no-new-privileges` (see architecture §6)
- [ ] `chmod 600 services/*/env/prod.env` and `scripts/.cloud-sync.env` (if used)
- [ ] Tailscale ACLs restricted to required tags/users
- [ ] Cron for `backup-all.sh` and `cloud-sync.sh`; webhooks tested
- [ ] Log rotation (json-file limits) verified on host disk budget

### Ongoing

- [ ] `make env-status` in routine ops; review backup/sync logs
- [ ] Test restores (Postgres, RabbitMQ, Meilisearch) on a schedule
- [ ] Revisit resource limits after `monitor-containers.sh` reports

---

## Further reading

| Document | Contents |
|:---------|:---------|
| **[architecture-prod.md](./architecture-prod.md)** | Full topology, limits, health intervals, DR, mermaid flow, deployment checklist |
| **`services/*/README.md`** | Service-specific runbooks |
| **`scripts/cron.md`** | Example cron entries |
| **`scripts/rclone.md`** | B2 / `rclone` configuration |

---

<div align="center">

**Production Docker stack for Nestlancer** · Spec: **[architecture-prod.md](./architecture-prod.md)**

<sub>Structure blended from internal <code>infrastructure/README.md</code> + <code>user-guide.md</code> patterns (prod-only); header style inspired by <a href="https://github.com/nestlancer/nestlancer-armory/blob/5368e09b73fc59d59bb6f5c03aa429bf15406077/monitoring/nest-sentinel/readme.md">Nest Sentinel</a>.</sub>

</div>
