# ClamAV Service Unit (Prod Only)

Antivirus engine with custom memory optimizations and hourly signature updates (`FRESHCLAM_CHECKS=24`).

## Quick Start

```bash
make up ENV=prod      # Start ClamAV
make logs ENV=prod    # Tail logs
```

## Available Makefile Targets

| Target | Description |
|---|---|
| `make up ENV=prod` | Start ClamAV |
| `make down ENV=prod` | Stop ClamAV |
| `make restart ENV=prod` | Restart |
| `make logs ENV=prod` | Tail logs |
| `make status ENV=prod` | Show status + health |
| `make clean ENV=prod` | Remove container + volume |

## Usage (Scanning)

The service runs a `clamd` daemon listening on TCP port `3310`. You can interact with it using `clamdscan` (from another container) or by sending raw TCP commands (e.g., `PING`, `VERSION`, `SCAN /path`).

## Signature Updates

- **Freshclam**: The container runs `freshclam` in the background to keep virus definitions up to date.
- **Frequency**: Controlled by `FRESHCLAM_CHECKS` (default: 24 times/day).
- **Initial Update**: On first start, the container will download the initial signature database. Use `CLAMAV_NO_FRESHCLAM_CHECK=true` to skip this (not recommended).

## Environment Variables

| Variable | Description | Default |
|---|---|---|
| `CLAMAV_NO_FRESHCLAM_CHECK` | Skip initial update | `false` |
| `FRESHCLAM_CHECKS` | Updates per day | `24` |
| `CLAMAV_MEMORY_LIMIT` | Hard memory limit | `2GB` |

## Healthcheck

The container uses a custom healthcheck (`healthcheck.sh`) that performs a TCP `PING` to the `clamd` daemon on port `3310` and expects a `PONG` response.

## Port Mapping

| Environment | Host Port | Container Port |
|---|---|---|
| prod | `3310` | `3310` |
