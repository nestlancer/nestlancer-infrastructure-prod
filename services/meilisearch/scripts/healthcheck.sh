#!/usr/bin/env bash
set -euo pipefail

# Meilisearch healthcheck
# http://localhost:7700/health

# Meilisearch has a /health endpoint that returns status: "available"
STATUS=$(curl -s http://localhost:7700/health | grep -o '"status":"available"' || true)

if [[ "$STATUS" == '"status":"available"' ]]; then
    exit 0
else
    echo "Meilisearch health check failed"
    exit 1
fi
