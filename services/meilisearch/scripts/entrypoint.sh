#!/usr/bin/env bash
set -euo pipefail

# ═══════════════════════════════════════════════════════════════
# Meilisearch Custom Entrypoint
# ═══════════════════════════════════════════════════════════════

echo "🚀 Starting Meilisearch..."
exec meilisearch "$@"
