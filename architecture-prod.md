# Infrastructure Architecture - PROD Environment

> **Last updated:** 2026-04-04  
> **Project:** Nestlancer Infrastructure - Production Environment  
> **Purpose:** Production workloads with maximum security and reliability

---

## Table of Contents

1. [PROD Environment Overview](#1-prod-environment-overview)
2. [Container Inventory (7 Containers)](#2-container-inventory-7-containers)
3. [Port Mapping & Access Strategy](#3-port-mapping--access-strategy)
4. [Network Architecture](#4-network-architecture)
5. [Volume & Data Persistence](#5-volume--data-persistence)
6. [Security Hardening](#6-security-hardening)
7. [Health Checks](#7-health-checks)
8. [Resource Limits](#8-resource-limits)
9. [Compose File Strategy](#9-compose-file-strategy)
10. [Service Catalog](#10-service-catalog)
11. [Tailscale VPN & Remote Access](#11-tailscale-vpn--remote-access)
12. [Backup & Disaster Recovery](#12-backup--disaster-recovery)
13. [Monitoring & Alerting](#13-monitoring--alerting)
14. [Operational Procedures](#14-operational-procedures)
15. [Makefile Commands](#15-makefile-commands)
16. [Directory Structure](#16-directory-structure)

---

## 1. PROD Environment Overview

The production environment provides a **hardened, zero-trust, fully isolated infrastructure** with 7 containers running on a single Docker host. This environment prioritizes security, reliability, and operational excellence.

```
┌─────────────────────────────────────────────────────────────────────┐
│                    PROD ENVIRONMENT (172.22.x.x)                    │
│                                                                     │
│  ┌───────────────────────────────────────────────────────────┐     │
│  │               7 Production Containers                       │     │
│  │                                                             │     │
│  │  • postgres-prod           (Primary Database)              │     │
│  │  • postgres-replica-prod   (Read Replica)                  │     │
│  │  • redis-cache-prod        (Application Cache)             │     │
│  │  • redis-pubsub-prod       (Real-time Messaging)           │     │
│  │  • rabbitmq-prod           (Message Queue)                 │     │
│  │  • meilisearch-prod        (Search Engine)                 │     │
│  │  • clamav-prod             (Antivirus Scanner)             │     │
│  │                                                             │     │
│  └─────────────────┬───────────────────────────────────────────┘     │
│                    │                                                 │
│         Connected via gateway_prod_network (172.22.0.0/24)          │
│         ZERO HOST PORTS — Access ONLY via Tailscale VPN subnet      │
│         Full security hardening: read-only rootfs, dropped caps     │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### Key Characteristics

| Property | Value |
|:---|:---|
| **Total Containers** | 7 |
| **Gateway Subnet** | `172.22.0.0/24` |
| **Host Port Exposure** | ❌ **NONE** (zero external exposure) |
| **Access Method** | 🔐 Tailscale VPN subnet routing |
| **Restart Policy** | `unless-stopped` / `always` |
| **Resource Limits** | ✅ **Enforced** (CPU + Memory) |
| **Security Hardening** | ✅ **FULL** (read-only, cap_drop, no-new-privileges) |
| **Logging** | JSON file with rotation (10MB, 3 files) |
| **Read-Only Rootfs** | ✅ Yes (PostgreSQL, Redis) |
| **Email Service** | ❌ NO Mailpit (prod uses real SMTP) |
| **Object Storage** | ❌ NO MinIO (prod uses Backblaze B2 / real S3) |
| **Search Engine** | ✅ Meilisearch (always deployed) |
| **Antivirus** | ✅ ClamAV (always deployed) |

### Differences from DEV/TEST

| Feature | DEV | TEST | PROD |
|:---|:---|:---|:---|
| **Host Ports** | Exposed | Exposed (offset) | **NONE** |
| **Access Method** | localhost | localhost | **Tailscale VPN** |
| **Security** | Minimal | Minimal | **Full hardening** |
| **Resource Limits** | None | Enforced | **Strictly enforced** |
| **Restart Policy** | unless-stopped | no | **always** |
| **Mailpit** | ✅ Yes | ✅ Yes | ❌ NO |
| **MinIO** | ✅ Yes | ✅ Yes | ❌ NO |
| **Meilisearch** | Optional | Optional | ✅ **Always** |
| **ClamAV** | Optional | Optional | ✅ **Always** |
| **Backups** | Manual | None | **Automated (cron)** |
| **Cloud Sync** | No | No | ✅ **Backblaze B2** |
| **Log Rotation** | No | No | ✅ **Yes** |

---

## 2. Container Inventory (7 Containers)

| # | Container Name | Service | Image | Purpose |
|:---:|:---|:---|:---|:---|
| 1 | `postgres-prod` | PostgreSQL Primary | Custom | Primary relational database |
| 2 | `postgres-replica-prod` | PostgreSQL Replica | Custom | Read-only replica (HA) |
| 3 | `redis-cache-prod` | Redis Cache | Custom | Application caching layer |
| 4 | `redis-pubsub-prod` | Redis Pub/Sub | Custom | Real-time event messaging |
| 5 | `rabbitmq-prod` | RabbitMQ | Custom | Durable message queue |
| 6 | `meilisearch-prod` | Meilisearch | Custom | Full-text search engine |
| 7 | `clamav-prod` | ClamAV | Custom | Antivirus/malware scanner |

**Services NOT in PROD:**
- ❌ Mailpit (dev/test only)
- ❌ MinIO (dev/test only; prod uses real cloud storage)

---

## 3. Port Mapping & Access Strategy

### 3.1 NO Host Ports Exposed

**PRODUCTION HAS ZERO HOST PORT MAPPINGS.**

```yaml
# Typical PROD service (PostgreSQL example)
services:
  postgres:
    # NO ports section
    # NO "5432:5432"
    # Access ONLY via Docker network
```

| Service | Container Port | Host Port | Status |
|:---|:---:|:---:|:---|
| **PostgreSQL** | `5432` | **None** | ❌ Not exposed |
| **Redis Cache** | `6379` | **None** | ❌ Not exposed |
| **Redis Pub/Sub** | `6379` | **None** | ❌ Not exposed |
| **RabbitMQ** | `5672`, `15672` | **None** | ❌ Not exposed |
| **Meilisearch** | `7700` | **None** | ❌ Not exposed |
| **ClamAV** | `3310` | **None** | ❌ Not exposed |

### 3.2 Access via Tailscale VPN

All production services are accessed via **Tailscale subnet routing**:

```
Developer Machine ──── Tailscale VPN ──── Docker Host ──── Docker Network ──── Container
                      (100.x.x.x)       (subnet router)   (172.22.x.x)      (static IP)
```

**Advertised Subnets:**
- `172.22.0.0/24` (gateway_prod_network)
- `172.22.1.0/28` (pg_internal_prod)
- `172.22.2.0/28` (rc_internal_prod)
- `172.22.3.0/28` (rp_internal_prod)
- `172.22.4.0/28` (rmq_internal_prod)
- `172.22.5.0/28` (meili_internal_prod)
- `172.22.6.0/28` (clam_internal_prod)

### 3.3 Connection Strings (via Tailscale)

```bash
# PostgreSQL Primary (via gateway network)
postgresql://nl_platform_app:password@postgres-prod.gateway_prod_network:5432/nl_platform_prod

# Or via static IP (direct)
postgresql://nl_platform_app:password@172.22.1.2:5432/nl_platform_prod

# Redis Cache
redis-cli -h 172.22.2.2 -p 6379 -a <password>

# RabbitMQ Management (via Tailscale browser)
http://rabbitmq-prod.gateway_prod_network:15672
# or
http://172.22.4.2:15672
```

### 3.4 Setting Up Tailscale Access

```bash
# On Docker host
cd nestlancer-infrastructure-prod/scripts
sudo ./tailscale-setup.sh

# This will:
# 1. Detect all prod networks
# 2. Enable IP forwarding
# 3. Advertise routes via Tailscale
# 4. Configure firewall rules
```

**On Your Machine (macOS/Windows/Linux):**
1. Install Tailscale
2. Join your Tailscale network
3. Approve advertised subnet routes in Tailscale admin console
4. Access containers directly via `172.22.x.x` IPs

---

## 4. Network Architecture

### 4.1 Network Topology

```
                    ┌─────────────────────────────────────┐
                    │    gateway_prod_network             │
                    │    172.22.0.0/24                    │
                    │    (ALL containers connect here)    │
                    │    Advertised via Tailscale         │
                    └─┬────┬────┬────┬────┬────┬────┬────┘
                      │    │    │    │    │    │    │
              ┌───────┴┐┌──┴──┐┌┴───┐┌┴───┐┌┴───┐┌┴──┐┌┴────┐
              │postgres││redis││redis││rmq ││meili││clam││     │
              │+replica││cache││pub/ ││    ││    ││    ││     │
              │        ││     ││sub  ││    ││    ││    ││     │
              └────┬───┘└──┬──┘└┬───┘└┬───┘└┬───┘└┬───┘     │
                   │       │    │     │     │     │          │
              ┌────┴───┐┌──┴──┐┌┴───┐┌┴───┐┌┴───┐┌┴───┐     │
              │pg_int_ ││rc_  ││rp_ ││rmq_││meili││clam││     │
              │prod    ││int_ ││int_││int_││_int_││_int││     │
              │(internal)│prod││prod││prod││prod ││prod││     │
              │172.22.1││.2  ││.3  ││.4  ││.5   ││.6  ││     │
              └─────────┘└────┘└────┘└────┘└────┘└────┘     │
                   │       │    │     │     │     │          │
                   └───────┴────┴─────┴─────┴─────┴──────────┘
                                    │
                            Tailscale VPN Subnet Router
                                    │
                          Remote Administrators / Apps
```

### 4.2 Network Inventory

| # | Network Name | Subnet | Driver | Internal | Advertised via Tailscale | Connected Services |
|:---:|:---|:---|:---|:---:|:---:|:---|
| 1 | `gateway_prod_network` | `172.22.0.0/24` | bridge | ❌ No | ✅ Yes | All 7 containers |
| 2 | `pg_internal_prod` | `172.22.1.0/28` | bridge | ✅ Yes | ✅ Yes | postgres-prod, postgres-replica-prod |
| 3 | `rc_internal_prod` | `172.22.2.0/28` | bridge | ✅ Yes | ✅ Yes | redis-cache-prod |
| 4 | `rp_internal_prod` | `172.22.3.0/28` | bridge | ✅ Yes | ✅ Yes | redis-pubsub-prod |
| 5 | `rmq_internal_prod` | `172.22.4.0/28` | bridge | ✅ Yes | ✅ Yes | rabbitmq-prod |
| 6 | `meili_internal_prod` | `172.22.5.0/28` | bridge | ✅ Yes | ✅ Yes | meilisearch-prod |
| 7 | `clam_internal_prod` | `172.22.6.0/28` | bridge | ✅ Yes | ✅ Yes | clamav-prod |

### 4.3 Static IP Assignments

| Container | Network | Static IP | Purpose |
|:---|:---|:---|:---|
| `postgres-prod` | `pg_internal_prod` | `172.22.1.2` | Primary DB (write) |
| `postgres-replica-prod` | `pg_internal_prod` | `172.22.1.3` | Replica DB (read-only) |
| `redis-cache-prod` | `rc_internal_prod` | `172.22.2.2` | Cache |
| `redis-pubsub-prod` | `rp_internal_prod` | `172.22.3.2` | Pub/Sub |
| `rabbitmq-prod` | `rmq_internal_prod` | `172.22.4.2` | Message queue |
| `meilisearch-prod` | `meili_internal_prod` | `172.22.5.2` | Search |
| `clamav-prod` | `clam_internal_prod` | `172.22.6.2` | AV scanner |

### 4.4 Network Creation

```bash
# Create all PROD networks
cd nestlancer-infrastructure-prod/networks
./create-networks.sh prod

# Or via root Makefile
make networks-create ENV=prod
```

---

## 5. Volume & Data Persistence

All persistent data is stored under:

```
/root/Desktop/docker-infra-data/prod/{service}/
```

### 5.1 Data Volume Map

| Service | Host Path | Container Path | Backup Frequency |
|:---|:---|:---|:---|
| **PostgreSQL Primary** | `{BASE}/prod/postgres/pg_data` | `/var/lib/postgresql/data` | Daily (2:00 AM) |
| **PostgreSQL Replica** | `{BASE}/prod/postgres/pg_replica_data` | `/var/lib/postgresql/data` | N/A (replica) |
| **PostgreSQL Backups** | `{BASE}/prod/postgres/pg_backups` | `/var/lib/postgresql/backups` | Synced to B2 (3:00 AM) |
| **Redis Cache** | `{BASE}/prod/redis-cache/rc_data` | `/data` | Not backed up (cache) |
| **Redis Pub/Sub** | `{BASE}/prod/redis-pubsub/rp_data` | `/data` | Not backed up (ephemeral) |
| **RabbitMQ Data** | `{BASE}/prod/rabbitmq/rmq_data` | `/var/lib/rabbitmq` | Daily (2:00 AM) |
| **RabbitMQ Backups** | `{BASE}/prod/rabbitmq/rmq_backups` | `/var/lib/rabbitmq/backups` | Synced to B2 (3:00 AM) |
| **Meilisearch Data** | `{BASE}/prod/meilisearch/meili_data` | `/meili_data` | Daily (2:00 AM) |
| **Meilisearch Dumps** | `{BASE}/prod/meilisearch/meili_data/dumps` | `/meili_data/dumps` | Synced to B2 (3:00 AM) |
| **ClamAV Definitions** | `{BASE}/prod/clamav/clam_data` | `/var/lib/clamav` | Auto-updated (freshclam 24x/day) |

### 5.2 Backup Storage

| Data Type | Retention (Local) | Retention (Cloud) | Sync Destination |
|:---|:---|:---|:---|
| **PostgreSQL dumps** | 7 days | 90 days | Backblaze B2: `nl-infra-services-prod-backup/postgres/` |
| **RabbitMQ exports** | 7 days | 90 days | Backblaze B2: `nl-infra-services-prod-backup/rabbitmq/` |
| **Meilisearch dumps** | 7 days | 90 days | Backblaze B2: `nl-infra-services-prod-backup/meilisearch/` |

---

## 6. Security Hardening

The PROD environment implements **defense-in-depth** security:

### 6.1 Container Security Profile

#### PostgreSQL (Primary & Replica)

```yaml
read_only: true                         # Rootfs is immutable
tmpfs:
  - /tmp                                # Writable temp dirs
  - /run
security_opt:
  - no-new-privileges:true              # Prevent privilege escalation
cap_drop:
  - ALL                                 # Drop all capabilities
cap_add:                                # Add back ONLY required caps
  - CHOWN
  - SETUID
  - SETGID
  - FOWNER
  - DAC_READ_SEARCH
  - DAC_OVERRIDE
stop_grace_period: 2m                   # Graceful shutdown
```

#### Redis (Cache & Pub/Sub)

```yaml
read_only: true
tmpfs:
  - /tmp
  - /run
security_opt:
  - no-new-privileges:true
cap_drop:
  - ALL
cap_add:
  - SETUID
  - SETGID
```

#### RabbitMQ

```yaml
restart: always                         # Always restart on failure
# Resource limits enforced
# No host ports
```

#### Meilisearch

```yaml
# Minimal security (runs as non-root by default)
# Resource limits enforced
```

#### ClamAV

```yaml
# Minimal security (runs as clamav user)
# Resource limits enforced
```

### 6.2 Security Features Summary

| Feature | PostgreSQL | Redis | RabbitMQ | Meilisearch | ClamAV |
|:---|:---:|:---:|:---:|:---:|:---:|
| **Read-Only Rootfs** | ✅ | ✅ | ❌ | ❌ | ❌ |
| **Tmpfs Mounts** | ✅ | ✅ | ❌ | ❌ | ❌ |
| **No-New-Privileges** | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Capability Dropping** | ✅ | ✅ | ❌ | ❌ | ❌ |
| **Resource Limits** | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Log Rotation** | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Host Port Exposure** | ❌ | ❌ | ❌ | ❌ | ❌ |

### 6.3 Logging Configuration

```yaml
logging:
  driver: json-file
  options:
    max-size: "10m"
    max-file: "3"
    tag: "postgres-prod"  # Service-specific tag
```

**Total log storage per service:** 30MB (10MB × 3 files)

### 6.4 Credential Management

**Production credentials are stored in:**
```
services/{service}/env/prod.env
```

**Credential Requirements:**
- ✅ Minimum 16 characters
- ✅ Mix of uppercase, lowercase, numbers, special chars
- ✅ Unique per service
- ✅ Rotated every 90 days
- ✅ Never committed to git (`.gitignore` enforced)

**Example (DO NOT USE THESE):**
```bash
# PostgreSQL
POSTGRES_PASSWORD=<GENERATE_STRONG_PASSWORD>

# Redis Cache
REDIS_PASSWORD=<GENERATE_STRONG_PASSWORD>

# RabbitMQ
RABBITMQ_DEFAULT_PASS=<GENERATE_STRONG_PASSWORD>

# Meilisearch
MEILI_MASTER_KEY=<GENERATE_STRONG_MASTER_KEY>
```

### 6.5 Network Security

| Rule | Status | Notes |
|:---|:---:|:---|
| **No host port exposure** | ✅ | All services internal-only |
| **Internal networks** | ✅ | Per-service isolation |
| **Tailscale ACLs** | ⚠️ | Configure in Tailscale admin console |
| **Host firewall** | ✅ | Configured by `tailscale-setup.sh` |

---

## 7. Health Checks

All services have **production-tuned health checks** with longer start periods.

### 7.1 Health Check Configuration

| Service | Test Command | Interval | Timeout | Retries | Start Period |
|:---|:---|:---:|:---:|:---:|:---:|
| **PostgreSQL** | `/usr/local/bin/healthcheck.sh` | `30s` | `10s` | `5` | `45s` |
| **PostgreSQL Replica** | `/usr/local/bin/healthcheck.sh` | `30s` | `10s` | `5` | `60s` |
| **Redis Cache** | `/usr/local/bin/healthcheck.sh` | `30s` | `10s` | `5` | `15s` |
| **Redis Pub/Sub** | `/usr/local/bin/healthcheck.sh` | `30s` | `10s` | `5` | `15s` |
| **RabbitMQ** | `/usr/local/bin/healthcheck.sh` | `30s` | `20s` | `10` | `60s` |
| **Meilisearch** | `/usr/local/bin/healthcheck.sh` | `30s` | `10s` | `5` | `15s` |
| **ClamAV** | `/usr/local/bin/healthcheck.sh` | `60s` | `10s` | `3` | `5m` |

### 7.2 Monitoring Health

```bash
# Check all PROD container health
make status ENV=prod

# Or using orchestrator
cd orchestrator
./status.sh | grep prod

# Docker native
docker ps --filter "name=prod" --format "table {{.Names}}\t{{.Status}}"
```

---

## 8. Resource Limits

**RESOURCE LIMITS ARE STRICTLY ENFORCED** in production.

### 8.1 Core Services

| Service | CPU Limit | Memory Limit | CPU Reservation | Memory Reservation |
|:---|:---|:---|:---|:---|
| **PostgreSQL** | `0.5` | `1GB` | `0.25` | `512MB` |
| **PostgreSQL Replica** | `0.25` | `512MB` | `0.1` | `256MB` |
| **Redis Cache** | `0.25` | `512MB` | `0.1` | `256MB` |
| **Redis Pub/Sub** | `0.25` | `256MB` | `0.1` | `128MB` |
| **RabbitMQ** | `0.5` | `1GB` | `0.2` | `512MB` |
| **Meilisearch** | `0.5` | `1GB` | `0.25` | `512MB` |
| **ClamAV** | `1.0` | `2.5GB` | `0.5` | `1.5GB` |

### 8.2 Total Resource Consumption

| Metric | Reserved | Limit |
|:---|:---|:---|
| **Total CPU** | ~2.4 cores | ~3.75 cores |
| **Total Memory** | ~4.3GB | ~7.75GB |

**Recommended Host Specs:**
- CPU: 4+ cores
- RAM: 16GB
- Disk: 100GB SSD

---

## 9. Compose File Strategy

Each service uses:

```
services/{service}/compose/
├── docker-compose.yml        # BASE (shared)
└── docker-compose.prod.yml   # PROD overrides (security, resources, NO ports)
```

### 9.1 Merge Pattern

```bash
docker compose \
  -f compose/docker-compose.yml \
  -f compose/docker-compose.prod.yml \
  --env-file env/prod.env \
  -p {service}-prod \
  up -d --build
```

### 9.2 What PROD Override Contains

```yaml
# docker-compose.prod.yml (example)
services:
  postgres:
    container_name: postgres-prod
    restart: unless-stopped
    # NO ports section (no host exposure)
    read_only: true
    tmpfs:
      - /tmp
      - /run
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
    cap_add:
      - CHOWN
      - SETUID
      - SETGID
    stop_grace_period: 2m
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"
        tag: "postgres-prod"
    deploy:
      resources:
        limits:
          cpus: '0.5'
          memory: 1G
        reservations:
          cpus: '0.25'
          memory: 512M
    networks:
      gateway_prod_network:
      pg_internal_prod:
        ipv4_address: 172.22.1.2
```

---

## 10. Service Catalog

### 10.1 PostgreSQL

**Image:** Custom (`services/postgres/docker/Dockerfile`)

```yaml
Container Port: 5432
Host Port: None (access via Tailscale)
Database Names: nl_maintenance_prod, nl_platform_prod
Users Created:
  - nl_infra_admin (superuser)
  - nl_platform_app (app user)
  - nl_analytics_readonly (read-only)
  - nl_replication_service (replication)

Security:
  - Read-only rootfs: YES
  - Capabilities: Minimal (CHOWN, SETUID, SETGID, FOWNER, DAC_*)
  - Stop grace: 2 minutes

Resource Limits:
  - CPU: 0.5 cores (limit), 0.25 cores (reserved)
  - Memory: 1GB (limit), 512MB (reserved)

Backup:
  - Automated daily at 2:00 AM
  - Retention: 7 days local, 90 days cloud (B2)
```

**Connection (via Tailscale):**
```bash
postgresql://nl_platform_app:password@172.22.1.2:5432/nl_platform_prod
```

### 10.2 Redis Cache

**Image:** Custom (`services/redis-cache/docker/Dockerfile`)

```yaml
Container Port: 6379
Host Port: None
Role: Application caching

Config:
  - Max memory: 400MB
  - Eviction policy: allkeys-lru
  - Persistence: RDB + AOF
  - Log level: warning

Security:
  - Read-only rootfs: YES
  - Capabilities: SETUID, SETGID only

Resource Limits:
  - CPU: 0.25 cores
  - Memory: 512MB
```

**Connection (via Tailscale):**
```bash
redis-cli -h 172.22.2.2 -p 6379 -a <password>
```

### 10.3 Redis Pub/Sub

**Image:** Custom (`services/redis-pubsub/docker/Dockerfile`)

```yaml
Container Port: 6379
Host Port: None
Role: Real-time pub/sub messaging

Config:
  - Max memory: 200MB
  - Persistence: RDB (ephemeral)
  - Log level: warning

Security:
  - Read-only rootfs: YES
  - Capabilities: SETUID, SETGID only

Resource Limits:
  - CPU: 0.25 cores
  - Memory: 256MB
```

### 10.4 RabbitMQ

**Image:** Custom (`services/rabbitmq/docker/Dockerfile`)

```yaml
Container Ports: 5672 (AMQP), 15672 (Management)
Host Ports: None
Role: Durable message queue

Config:
  - Node name: rabbit@rabbitmq-prod
  - Plugins: management, prometheus, shovel, federation
  - Restart: always

Resource Limits:
  - CPU: 0.5 cores (limit), 0.2 cores (reserved)
  - Memory: 1GB (limit), 512MB (reserved)

Backup:
  - Automated daily at 2:00 AM (definitions export)
  - Retention: 7 days local, 90 days cloud
```

**Access (via Tailscale):**
```bash
# Management UI
http://172.22.4.2:15672

# AMQP
amqp://nl_infra_admin:password@172.22.4.2:5672
```

### 10.5 Meilisearch

**Image:** Custom (`services/meilisearch/docker/Dockerfile`)

```yaml
Container Port: 7700
Host Port: None
Role: Full-text search engine

Config:
  - Environment: production
  - Master key: <strong_master_key>
  - Max indexing memory: 1GB

Resource Limits:
  - CPU: 0.5 cores (limit), 0.25 cores (reserved)
  - Memory: 1GB (limit), 512MB (reserved)

Backup:
  - Automated daily at 2:00 AM (dump creation)
  - Retention: 7 days local, 90 days cloud
```

**Access (via Tailscale):**
```bash
# API
http://172.22.5.2:7700

# Health check
curl -H "Authorization: Bearer <master_key>" http://172.22.5.2:7700/health
```

### 10.6 ClamAV

**Image:** Custom (`services/clamav/docker/Dockerfile`)

```yaml
Container Port: 3310
Host Port: None
Role: Antivirus/malware scanning

Config:
  - Start period: 5 minutes (virus DB load time)
  - Freshclam: 24 checks/day
  - Max file size: 100MB
  - Max scan size: 500MB

Resource Limits:
  - CPU: 1.0 core (limit), 0.5 cores (reserved)
  - Memory: 2.5GB (limit), 1.5GB (reserved)
```

**Usage (from another container):**
```bash
# Scan a file
docker exec -it clamav-prod clamdscan /path/to/file

# Or via clamd socket
nc 172.22.6.2 3310
```

---

## 11. Tailscale VPN & Remote Access

### 11.1 Setup Tailscale Subnet Routing

```bash
# On Docker host
cd nestlancer-infrastructure-prod/scripts
sudo ./tailscale-setup.sh

# Expected output:
# ✅ Detected 7 production networks
# ✅ Enabled IP forwarding
# ✅ Advertising routes: 172.22.0.0/24, 172.22.1.0/28, ...
# ✅ Configured firewall rules
# ✅ Tailscale subnet routing active
```

**What the script does:**
1. Detects all `*_prod*` Docker networks
2. Enables kernel IP forwarding (`net.ipv4.ip_forward=1`)
3. Runs `tailscale up --advertise-routes=172.22.0.0/24,...`
4. Configures iptables/nftables to allow Tailscale traffic
5. Persists settings across reboots

### 11.2 Approve Routes in Tailscale Admin

1. Go to https://login.tailscale.com/admin/machines
2. Find your Docker host
3. Click "Edit route settings"
4. Approve advertised subnets:
   - `172.22.0.0/24` ✅
   - `172.22.1.0/28` ✅
   - `172.22.2.0/28` ✅
   - `172.22.3.0/28` ✅
   - `172.22.4.0/28` ✅
   - `172.22.5.0/28` ✅
   - `172.22.6.0/28` ✅

### 11.3 Access from Your Machine

**Prerequisites:**
- Tailscale installed on your machine
- Connected to the same Tailscale network

**Connect to PostgreSQL:**
```bash
psql -h 172.22.1.2 -p 5432 -U nl_platform_app -d nl_platform_prod
```

**Connect to Redis:**
```bash
redis-cli -h 172.22.2.2 -p 6379 -a <password>
```

**Access RabbitMQ Management UI:**
```bash
# In your browser (via Tailscale)
http://172.22.4.2:15672
```

**Access Meilisearch API:**
```bash
curl -H "Authorization: Bearer <master_key>" http://172.22.5.2:7700/health
```

### 11.4 Troubleshooting Tailscale

```bash
# Check Tailscale status
tailscale status

# Check advertised routes
tailscale status | grep "offering"

# Verify IP forwarding
sysctl net.ipv4.ip_forward  # Should be 1

# Test connectivity from remote machine
ping 172.22.1.2
telnet 172.22.1.2 5432
```

---

## 12. Backup & Disaster Recovery

### 12.1 Automated Local Backups

**Script:** `scripts/backup-all.sh`

**Schedule:** Daily at 2:00 AM (via cron)

```cron
# /etc/cron.d/infra-backups
0 2 * * * /root/Desktop/nestlancer-infrastructure-prod/scripts/backup-all.sh prod >/dev/null 2>&1
```

**What Gets Backed Up:**

| Service | Method | Destination | Format |
|:---|:---|:---|:---|
| **PostgreSQL** | `pg_dump` (all databases) | `/var/lib/postgresql/backups/` | `.sql.gz` |
| **RabbitMQ** | Definitions export | `/var/lib/rabbitmq/backups/` | `.json` |
| **Meilisearch** | Dump API | `/meili_data/dumps/` | `.dump` |

**Backup Files:**
```
postgres/pg_backups/
  ├── backup_20260404_020000.sql.gz
  ├── backup_20260405_020000.sql.gz
  └── ...

rabbitmq/rmq_backups/
  ├── backup_20260404_020000.json
  └── ...

meilisearch/meili_data/dumps/
  ├── 20260404-020000-123.dump
  └── ...
```

### 12.2 Cloud Sync (Backblaze B2)

**Script:** `scripts/cloud-sync.sh`

**Schedule:** Daily at 3:00 AM (after local backups complete)

```cron
# /etc/cron.d/infra-cloud-sync
0 3 * * * /root/Desktop/nestlancer-infrastructure-prod/scripts/cloud-sync.sh --quiet >/dev/null 2>&1
```

**Sync Targets:**

| Local Path | Remote Bucket | Remote Folder |
|:---|:---|:---|
| `postgres/pg_backups/` | `nl-infra-services-prod-backup` | `postgres/` |
| `rabbitmq/rmq_backups/` | `nl-infra-services-prod-backup` | `rabbitmq/` |
| `meilisearch/meili_data/dumps/` | `nl-infra-services-prod-backup` | `meilisearch/` |

**Retention:**
- Local: 7 days (automatic cleanup by backup script)
- Cloud: 90 days (manual cleanup: `cloud-sync.sh --cleanup`)

**Features:**
- ✅ Checksum verification after upload
- ✅ Lock file prevents concurrent runs
- ✅ Discord/Slack webhook alerts on success/failure
- ✅ Log rotation (50MB max, 5 files)
- ✅ Bandwidth limiting (configurable)
- ✅ Dry-run mode for testing

### 12.3 Backup Verification

```bash
# List remote backups
cd nestlancer-infrastructure-prod/scripts
./cloud-sync.sh --status

# Expected output:
# ========================================
# Last sync: 2026-04-04 03:05:32
# Files synced: 127
# Total size: 4.2 GB
# ========================================
```

### 12.4 Disaster Recovery Procedure

**Scenario: Total data loss**

```bash
# 1. Stop all production containers
make env-down ENV=prod

# 2. Remove corrupted volumes
make clean ENV=prod

# 3. Download latest backups from Backblaze B2
cd /root/Desktop/docker-infra-data/prod
rclone copy backblaze:nl-infra-services-prod-backup/postgres/ postgres/pg_backups/
rclone copy backblaze:nl-infra-services-prod-backup/rabbitmq/ rabbitmq/rmq_backups/
rclone copy backblaze:nl-infra-services-prod-backup/meilisearch/ meilisearch/meili_data/dumps/

# 4. Recreate networks
make networks-create ENV=prod

# 5. Start services
make env-up ENV=prod

# 6. Restore PostgreSQL
make postgres-restore ENV=prod FILE=/var/lib/postgresql/backups/backup_20260404_020000.sql.gz

# 7. Restore RabbitMQ
make rabbitmq-restore ENV=prod FILE=/var/lib/rabbitmq/backups/backup_20260404_020000.json

# 8. Restore Meilisearch
# (Meilisearch auto-loads dumps from /meili_data/dumps/ on startup)

# 9. Verify all services
make env-status ENV=prod
```

---

## 13. Monitoring & Alerting

### 13.1 Container Resource Monitor

**Script:** `scripts/monitor-containers.sh`

```bash
# Run 60-second sampling on PROD
cd nestlancer-infrastructure-prod/scripts
./monitor-containers.sh --duration 60 --env prod

# Output: reports/container-resources-prod-<timestamp>.md
```

**Report includes:**
- Average & peak CPU usage per container
- Average & peak memory usage per container
- Network I/O (RX/TX bytes)
- Block I/O (read/write bytes)
- Recommendations for resource limit adjustments

### 13.2 Health Dashboard

**Script:** `orchestrator/status.sh`

```bash
cd orchestrator
./status.sh

# or
make status ENV=prod
```

**Output:**
```
┌─────────────────────┬──────────┬──────────┬────────────────┬─────────┐
│ Container           │ State    │ Health   │ Ports          │ Uptime  │
├─────────────────────┼──────────┼──────────┼────────────────┼─────────┤
│ postgres-prod       │ running  │ healthy  │ (internal)     │ 5 days  │
│ postgres-replica... │ running  │ healthy  │ (internal)     │ 5 days  │
│ redis-cache-prod    │ running  │ healthy  │ (internal)     │ 5 days  │
│ ...                 │          │          │                │         │
└─────────────────────┴──────────┴──────────┴────────────────┴─────────┘
```

### 13.3 Alerting (Discord Webhooks)

**Configured in:**
- `scripts/backup-all.sh` (backup completion/failure)
- `scripts/cloud-sync.sh` (sync completion/failure)

**Webhook URL:** Set in script or as environment variable

**Alert Triggers:**
- ✅ Backup completion (success + per-service summary)
- ❌ Backup failure (service name + error message)
- ✅ Cloud sync completion (files synced + total size)
- ❌ Cloud sync failure (error details)

**Sample Alert (Success):**
```
🎉 Production Backup Completed Successfully
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Environment: prod
Timestamp: 2026-04-04 02:05:32

✅ PostgreSQL: backup_20260404_020000.sql.gz (256 MB)
✅ RabbitMQ: backup_20260404_020000.json (4.2 MB)
✅ Meilisearch: 20260404-020000-123.dump (128 MB)

Total: 388.2 MB
```

**Sample Alert (Failure):**
```
❌ Production Backup FAILED
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Environment: prod
Timestamp: 2026-04-04 02:05:32

Service: PostgreSQL
Error: pg_dump: connection to database failed

Please investigate immediately!
```

### 13.4 Log Aggregation

```bash
# View all PROD logs (last 100 lines, follow)
make env-logs ENV=prod

# View specific service logs
make postgres-logs ENV=prod
make rabbitmq-logs ENV=prod

# Or using Docker directly
docker logs -f --tail 100 postgres-prod
```

---

## 14. Operational Procedures

### 14.1 Starting Production Environment

```bash
# 1. Ensure networks exist
make networks-create ENV=prod

# 2. Start all services
make env-up ENV=prod

# 3. Wait for health checks
sleep 60

# 4. Verify status
make env-status ENV=prod

# 5. Check logs for errors
make env-logs ENV=prod | grep -i error
```

### 14.2 Stopping Production Environment

```bash
# Graceful shutdown (2-minute grace period for PostgreSQL)
make env-down ENV=prod

# Verify all containers stopped
docker ps --filter "name=prod"
```

### 14.3 Restarting a Single Service

```bash
# Restart PostgreSQL
make postgres-restart ENV=prod

# Restart RabbitMQ
make rabbitmq-restart ENV=prod

# Check health after restart
make postgres-status ENV=prod
```

### 14.4 Database Operations

**Connect to PostgreSQL (via Tailscale):**
```bash
psql -h 172.22.1.2 -p 5432 -U nl_infra_admin -d nl_platform_prod
```

**Manual Backup:**
```bash
make postgres-backup ENV=prod
```

**Restore from Backup:**
```bash
make postgres-restore ENV=prod FILE=/var/lib/postgresql/backups/backup_20260404_020000.sql.gz
```

**Replication Status:**
```bash
docker exec -it postgres-prod psql -U nl_infra_admin -d postgres -c "SELECT * FROM pg_stat_replication;"
```

### 14.5 Cache Operations

**Flush Redis Cache:**
```bash
# Via Tailscale
redis-cli -h 172.22.2.2 -p 6379 -a <password> FLUSHDB

# Or from host via Docker exec
docker exec -it redis-cache-prod redis-cli -a <password> FLUSHDB
```

**Monitor Redis:**
```bash
redis-cli -h 172.22.2.2 -p 6379 -a <password> INFO
redis-cli -h 172.22.2.2 -p 6379 -a <password> MONITOR
```

### 14.6 Queue Operations

**RabbitMQ Management:**
```bash
# Access UI (via Tailscale)
http://172.22.4.2:15672

# List queues
docker exec -it rabbitmq-prod rabbitmqctl list_queues

# Purge a queue
docker exec -it rabbitmq-prod rabbitmqctl purge_queue queue_name
```

### 14.7 Search Operations

**Meilisearch Dumps:**
```bash
# Create manual dump
curl -X POST "http://172.22.5.2:7700/dumps" \
  -H "Authorization: Bearer <master_key>"

# List dumps
ls -lh /root/Desktop/docker-infra-data/prod/meilisearch/meili_data/dumps/
```

### 14.8 Antivirus Operations

**Update Virus Definitions:**
```bash
docker exec -it clamav-prod freshclam
```

**Scan a File:**
```bash
# From host
docker exec -it clamav-prod clamdscan /path/to/file

# From another container
docker exec -it postgres-prod sh -c "echo 'test' > /tmp/test.txt"
docker exec -it clamav-prod clamdscan /shared/test.txt
```

### 14.9 Emergency Procedures

**Service Unresponsive:**
```bash
# 1. Check container state
docker ps -a | grep <service>-prod

# 2. Check logs
docker logs --tail 200 <service>-prod

# 3. Restart service
make <service>-restart ENV=prod

# 4. If restart fails, rebuild
make <service>-down ENV=prod
make <service>-up ENV=prod
```

**Disk Full:**
```bash
# 1. Check disk usage
df -h
du -sh /root/Desktop/docker-infra-data/prod/*

# 2. Clean old backups
find /root/Desktop/docker-infra-data/prod/postgres/pg_backups/ -name "*.sql.gz" -mtime +7 -delete

# 3. Prune Docker system
docker system prune -a --volumes

# 4. Rotate logs
docker logs <service>-prod > /dev/null 2>&1
```

**Total Infrastructure Failure:**
```bash
# 1. Stop everything
make env-down ENV=prod

# 2. Follow disaster recovery procedure (section 12.4)
```

---

## 15. Makefile Commands

All commands are run from the root `nestlancer-infrastructure-prod/` directory.

### 15.1 Environment-Level Commands

```bash
# Start all PROD services
make env-up ENV=prod

# Stop all PROD services
make env-down ENV=prod

# Restart all PROD services
make env-restart ENV=prod

# Show status of all PROD services
make env-status ENV=prod

# Show logs of all PROD services
make env-logs ENV=prod

# Clean (remove containers + volumes) — USE WITH CAUTION
make clean ENV=prod
```

### 15.2 Service-Specific Commands

**PostgreSQL:**
```bash
make postgres-up ENV=prod
make postgres-down ENV=prod
make postgres-restart ENV=prod
make postgres-logs ENV=prod
make postgres-shell ENV=prod
make postgres-status ENV=prod
make postgres-backup ENV=prod
make postgres-restore ENV=prod FILE=/path/to/backup.sql.gz
```

**Redis:**
```bash
make redis-cache-up ENV=prod
make redis-cache-down ENV=prod
make redis-cache-restart ENV=prod
make redis-cache-logs ENV=prod
make redis-cache-cli ENV=prod
```

**RabbitMQ:**
```bash
make rabbitmq-up ENV=prod
make rabbitmq-down ENV=prod
make rabbitmq-restart ENV=prod
make rabbitmq-logs ENV=prod
make rabbitmq-shell ENV=prod
make rabbitmq-backup ENV=prod
```

**Meilisearch:**
```bash
make meilisearch-up ENV=prod
make meilisearch-down ENV=prod
make meilisearch-restart ENV=prod
make meilisearch-logs ENV=prod
make meilisearch-backup ENV=prod
```

**ClamAV:**
```bash
make clamav-up ENV=prod
make clamav-down ENV=prod
make clamav-restart ENV=prod
make clamav-logs ENV=prod
make clamav-shell ENV=prod
```

### 15.3 Backup & DR Commands

```bash
# Run manual backup (all services)
cd scripts
./backup-all.sh prod

# Manual cloud sync
cd scripts
./cloud-sync.sh

# Verify cloud sync status
cd scripts
./cloud-sync.sh --status

# Dry-run sync (test without uploading)
cd scripts
./cloud-sync.sh --dry-run

# Cloud cleanup (remove old backups)
cd scripts
./cloud-sync.sh --cleanup
```

### 15.4 Monitoring Commands

```bash
# Resource monitor (60-second sample)
cd scripts
./monitor-containers.sh --duration 60 --env prod

# Status dashboard
make env-status ENV=prod

# Aggregate logs
make env-logs ENV=prod
```

### 15.5 Network Commands

```bash
# Create all PROD networks
make networks-create ENV=prod

# Destroy all PROD networks (BE CAREFUL)
make networks-destroy ENV=prod

# List all project networks
make networks-list
```

---

## 16. Directory Structure

```
nestlancer-infrastructure-prod/
├── Makefile
├── architecture-prod.md               # ← This file
│
├── services/
│   ├── postgres/
│   │   ├── compose/
│   │   │   ├── docker-compose.yml
│   │   │   └── docker-compose.prod.yml    # PROD overrides (security, NO ports)
│   │   ├── config/
│   │   │   └── prod/
│   │   │       ├── postgresql.conf        # Production tuning
│   │   │       └── pg_hba.conf            # Strict auth
│   │   ├── env/
│   │   │   └── prod.env                   # PROD credentials (GITIGNORED)
│   │   └── scripts/
│   │       ├── healthcheck.sh
│   │       ├── backup.sh
│   │       └── restore.sh
│   │
│   ├── redis-cache/
│   │   ├── compose/docker-compose.prod.yml  # Security, resource limits
│   │   ├── config/prod/redis.conf           # Production config
│   │   └── env/prod.env
│   │
│   ├── rabbitmq/
│   │   ├── compose/docker-compose.prod.yml
│   │   ├── config/prod/rabbitmq.conf
│   │   └── env/prod.env
│   │
│   ├── meilisearch/
│   │   ├── compose/docker-compose.prod.yml  # Always deployed in PROD
│   │   ├── env/prod.env
│   │   └── scripts/backup.sh
│   │
│   └── clamav/
│       ├── compose/docker-compose.prod.yml  # Always deployed in PROD
│       ├── config/prod/clamd.conf
│       └── env/prod.env
│
├── networks/
│   ├── create-networks.sh                   # Pass "prod" as argument
│   └── ...
│
├── orchestrator/
│   ├── start-all.sh                         # Start all PROD services
│   ├── stop-all.sh
│   └── status.sh
│
├── scripts/
│   ├── backup-all.sh                        # Automated backups (cron)
│   ├── cloud-sync.sh                        # Backblaze B2 sync (cron)
│   ├── monitor-containers.sh                # Resource monitoring
│   ├── optimize-host.sh                     # Kernel tuning
│   ├── tailscale-setup.sh                   # VPN subnet routing
│   └── cron.md                              # Cron job documentation
│
└── logs/
    ├── backups.log                          # Backup log history
    └── ai-prompt-prod.md
```

---

## Connection Flow Diagram

```mermaid
graph TB
    subgraph "Remote Access"
        ADMIN[Administrator<br>via Tailscale VPN]
        APP[Application Server<br>via Tailscale VPN]
    end

    subgraph "Tailscale Network"
        TS[Tailscale Subnet Router<br>Docker Host]
    end

    subgraph "PROD Environment (172.22.x.x)"
        GW[gateway_prod_network<br>172.22.0.0/24<br>NO HOST PORTS]
        
        PG[postgres-prod<br>172.22.1.2:5432]
        PGR[postgres-replica-prod<br>172.22.1.3:5432]
        RC[redis-cache-prod<br>172.22.2.2:6379]
        RP[redis-pubsub-prod<br>172.22.3.2:6379]
        RMQ[rabbitmq-prod<br>172.22.4.2:5672,:15672]
        MS[meilisearch-prod<br>172.22.5.2:7700]
        CV[clamav-prod<br>172.22.6.2:3310]
        
        GW --- PG
        GW --- PGR
        GW --- RC
        GW --- RP
        GW --- RMQ
        GW --- MS
        GW --- CV
    end

    subgraph "Backup & Recovery"
        LOCAL[Local Backups<br>pg_backups/, rmq_backups/]
        B2[Backblaze B2<br>nl-infra-services-prod-backup]
    end

    ADMIN -->|Tailscale 100.x.x.x| TS
    APP -->|Tailscale 100.x.x.x| TS
    TS -->|Advertised routes| GW

    PG -->|Daily 2:00 AM| LOCAL
    RMQ -->|Daily 2:00 AM| LOCAL
    MS -->|Daily 2:00 AM| LOCAL
    LOCAL -->|Daily 3:00 AM<br>rclone sync| B2

    style GW fill:#e74c3c,color:#fff
    style TS fill:#3498db,color:#fff
    style B2 fill:#9b59b6,color:#fff
```

---

## Production Deployment Checklist

- [ ] Review all credentials in `services/*/env/prod.env`
- [ ] Ensure strong passwords (16+ chars, mixed case, numbers, special)
- [ ] Run `make networks-create ENV=prod`
- [ ] Run `scripts/optimize-host.sh` (kernel tuning)
- [ ] Run `scripts/tailscale-setup.sh` (VPN subnet routing)
- [ ] Approve Tailscale subnet routes in admin console
- [ ] Run `make env-up ENV=prod`
- [ ] Wait ~120 seconds for all health checks (ClamAV takes 5 min)
- [ ] Run `make env-status ENV=prod`
- [ ] Test Tailscale connectivity from remote machine
- [ ] Configure cron jobs (backup + cloud sync)
- [ ] Configure Discord/Slack webhook URLs in backup scripts
- [ ] Test manual backup: `cd scripts && ./backup-all.sh prod`
- [ ] Test cloud sync: `cd scripts && ./cloud-sync.sh --dry-run`
- [ ] Verify backups appear in Backblaze B2
- [ ] Configure monitoring/alerting
- [ ] Document credentials in secure vault (1Password, Bitwarden, etc.)
- [ ] Schedule first DR drill
- [ ] Production is LIVE! 🚀

---
