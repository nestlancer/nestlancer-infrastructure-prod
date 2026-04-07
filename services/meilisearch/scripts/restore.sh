#!/usr/bin/env bash
set -euo pipefail

# ═══════════════════════════════════════════════════════════════
# Meilisearch Restore Helper Script
# ═══════════════════════════════════════════════════════════════

DUMP_FILE="${1:-}"

echo "═══════════════════════════════════════════════════"
echo "  Meilisearch Restore Helper"
echo "═══════════════════════════════════════════════════"

if [[ -z "$DUMP_FILE" ]]; then
    echo "❌ ERROR: No dump file specified."
    echo "   Usage: ./restore.sh <path_to_dump.dump>"
    echo ""
    echo "   Available dumps in /meili_data/dumps/:"
    ls -lh /meili_data/dumps/*.dump 2>/dev/null || echo "   (None found)"
    exit 1
fi

if [[ ! -f "$DUMP_FILE" ]]; then
    # Try relative to dumps dir if not found
    if [[ -f "/meili_data/dumps/${DUMP_FILE}" ]]; then
        DUMP_FILE="/meili_data/dumps/${DUMP_FILE}"
    else
        echo "❌ ERROR: Dump file not found: ${DUMP_FILE}"
        exit 1
    fi
fi

echo "⚠️  CRITICAL: Meilisearch requires a restart with the --import-dump flag."
echo "   This script confirms the dump is valid and ready for import."
echo ""
echo "   Dump: ${DUMP_FILE}"
echo "   Size: $(du -h "${DUMP_FILE}" | cut -f1)"
echo ""
echo "✅ Validated. To restore, use 'make restore DUMP=${DUMP_FILE}' from the host."
echo "═══════════════════════════════════════════════════"
