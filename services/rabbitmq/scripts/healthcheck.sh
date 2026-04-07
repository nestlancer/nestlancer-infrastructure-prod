#!/usr/bin/env bash
set -eo pipefail

# ═══════════════════════════════════════════════════════════════
# RabbitMQ Healthcheck — Diagnostics for Docker
# ═══════════════════════════════════════════════════════════════

# Use rabbitmq-diagnostics to check if the node is running
# -q: quiet mode (minimal output)
# check_running: verifies the node is started and application is running
if rabbitmq-diagnostics -q check_running; then
    exit 0
else
    exit 1
fi
