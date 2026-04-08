<div align="center">

# RabbitMQ Service Unit — Production

### Message broker · isolated 172.22.4.x network · management + prometheus

[![Docker](https://img.shields.io/badge/Docker-Compose-2496ED?style=for-the-badge&logo=docker&logoColor=white)](https://docs.docker.com/compose/)
[![Linux](https://img.shields.io/badge/Host-Linux-FCC624?style=for-the-badge&logo=linux&logoColor=black)](https://kernel.org/)

<br/>

**Production-ready**, self-contained RabbitMQ service with Management and Prometheus plugins enabled. This repository ships **production** configuration only (`ENV=prod` by default).

<br/>

[Quick Start](#quick-start) •
[Management UI](#management-ui) •
[Makefile Targets](#available-makefile-targets) •
[Ports](#port-mapping)

<br/>

---

</div>

<br/>

## Table of contents

<details>
<summary><b>Expand full outline</b></summary>

- [Quick Start](#quick-start)
- [Management UI](#management-ui)
- [Available Makefile Targets](#available-makefile-targets)
- [Port Mapping](#port-mapping)

</details>

---
## Quick Start

```bash
make up              # Start RabbitMQ (prod)
make shell           # Open rabbitmq-diagnostics shell
make logs            # Tail logs
```

## Management UI

Production exposes **no** management port on the host; access is from application containers on the internal / gateway networks only.

## Available Makefile Targets

| Target | Description |
|---|---|
| `make up` | Start RabbitMQ |
| `make down` | Stop RabbitMQ |
| `make restart` | Restart |
| `make logs` | Tail logs |
| `make shell` | Open diagnostics shell |
| `make status` | Show status + health |
| `make backup` | Export definitions to `backups/` |
| `make restore FILE=<path>` | Import definitions from file |
| `make build` | Build Docker image |
| `make rebuild` | Force rebuild |
| `make clean` | Remove container |

## Port Mapping

| AMQP (host) | Management (host) |
|---|---|
| **NONE** | **NONE** |
