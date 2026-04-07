#!/usr/bin/env bash
set -euo pipefail

# ═══════════════════════════════════════════════════════════════
# Meilisearch Backup Script — Trigger Dump via API
# ═══════════════════════════════════════════════════════════════

MEILI_ADDR="http://localhost:7700"
MEILI_MASTER_KEY="${MEILI_MASTER_KEY:-}"
DUMP_DIR="/meili_data/dumps"

echo "═══════════════════════════════════════════════════"
echo "  Meilisearch Backup (Dump)"
echo "  Endpoint: ${MEILI_ADDR}"
echo "═══════════════════════════════════════════════════"

# Trigger dump
echo "🚀 Triggering dump..."
RESPONSE=$(curl -s -X POST "${MEILI_ADDR}/dumps" \
  -H "Authorization: Bearer ${MEILI_MASTER_KEY}")

# Extract taskUid using sed (compatible with BusyBox)
TASK_UID=$(echo "$RESPONSE" | sed -n 's/.*"taskUid":\([0-9]*\).*/\1/p')

if [[ -z "$TASK_UID" ]]; then
    echo "❌ ERROR: Failed to trigger dump."
    echo "   Response: ${RESPONSE}"
    exit 1
fi

echo "⏳ Dump task created (UID: ${TASK_UID}). Waiting for completion..."
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
ENV_TAG="${APP_ENV:-unknown}"

# Poll task status
while true; do
    STATUS_RESPONSE=$(curl -s -X GET "${MEILI_ADDR}/tasks/${TASK_UID}" \
      -H "Authorization: Bearer ${MEILI_MASTER_KEY}")
    
    STATUS=$(echo "$STATUS_RESPONSE" | sed -n 's/.*"status":"\([^"]*\)".*/\1/p' || echo "unknown")
    
    if [[ "$STATUS" == "succeeded" ]]; then
        echo "✅ Dump completed successfully!"
        break
    elif [[ "$STATUS" == "failed" ]]; then
        echo "❌ ERROR: Dump task failed."
        echo "   Details: ${STATUS_RESPONSE}"
        exit 1
    elif [[ "$STATUS" == "unknown" ]]; then
        echo "⚠️  WARNING: Could not determine task status. Retrying..."
    else
        echo "   Status: ${STATUS}..."
    fi
    
    sleep 2
done

# Find the latest dump file and rename it
echo "🏷️  Renaming dump to standard format..."
# Meilisearch dumps are usually named as the date/time or a UID.
# We'll find the most recent .dump file in DUMP_DIR.
LATEST_DUMP=$(ls -dt "${DUMP_DIR}"/*.dump 2>/dev/null | head -n 1)

if [[ -n "$LATEST_DUMP" ]]; then
    NEW_DUMP_FILENAME="meilisearch-${ENV_TAG}-dump-${TIMESTAMP}.dump"
    NEW_DUMP_PATH="${DUMP_DIR}/${NEW_DUMP_FILENAME}"
    
    # Only rename if it's not already named correctly (avoid recursion/errors)
    if [[ "$(basename "$LATEST_DUMP")" != "$NEW_DUMP_FILENAME" ]]; then
        mv "$LATEST_DUMP" "$NEW_DUMP_PATH"
        echo "✅ Renamed: $(basename "$LATEST_DUMP") ➔ ${NEW_DUMP_FILENAME}"
    fi
else
    echo "⚠️  WARNING: Could not find the generated dump file to rename."
fi

# List existing dumps
echo ""
echo "📁 Available dumps in ${DUMP_DIR}:"
ls -lh "${DUMP_DIR}" 2>/dev/null || echo "   (No dumps found in ${DUMP_DIR})"
echo "═══════════════════════════════════════════════════"
