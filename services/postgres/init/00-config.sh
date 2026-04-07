#!/usr/bin/env bash
set -euo pipefail

# ═══════════════════════════════════════════════════════════════
# post-init-config.sh
# This script runs AFTER initdb completes but BEFORE the real server starts.
# It is placed in /docker-entrypoint-initdb.d/
# ═══════════════════════════════════════════════════════════════

echo "==> [Init Hook] Post-init initialization..."

if [ -f "/usr/local/bin/scripts/entrypoint.sh" ]; then
    echo "==> Running configuration merge from entrypoint script..."
    # Execute in a subshell to avoid exiting the sourcing shell (docker-entrypoint.sh)
    /usr/local/bin/scripts/entrypoint.sh --hook
fi
