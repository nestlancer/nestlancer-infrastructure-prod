# RabbitMQ Service Unit

Self-contained RabbitMQ service with Management and Prometheus plugins enabled. This repository ships **production** configuration only (`ENV=prod` by default).

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
