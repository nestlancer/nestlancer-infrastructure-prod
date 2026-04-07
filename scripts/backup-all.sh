#!/usr/bin/env bash
set -euo pipefail

# ═══════════════════════════════════════════════════════════════
# Master Backup Script — Trigger backups for all services
# ═══════════════════════════════════════════════════════════════

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$(dirname "$SCRIPTS_DIR")"
LOG_FILE="${INFRA_DIR}/logs/backups.log"
ENV="${1:-prod}"
ALERT_WEBHOOK_URL="https://discord.com/api/webhooks/1485114548414578839/4UeZC814A3zmUDg0XTD6T47GiIdMH81Zxx1JY_ctNBfvpR3JUyljTQ8ilduHk8buY970/slack"

TOTAL_BACKED_UP=0
TOTAL_FAILED=0
declare -A SERVICE_RESULTS=()
START_TIME=$(date +%s)

# Ensure log directory
mkdir -p "$(dirname "$LOG_FILE")"

# ═══════════════════════════════════════════════════════════════
#  Alert / Notification System
# ═══════════════════════════════════════════════════════════════
send_alert() {
    local status="$1" message="$2"
    if [[ -n "${ALERT_WEBHOOK_URL:-}" ]]; then
        local color icon
        if [[ "$status" == "SUCCESS" ]]; then
            color="#2ecc71"; icon="✅"
        else
            color="#e74c3c"; icon="🚨"
        fi
        
        local payload
        payload=$(cat <<-PAYLOAD
{
    "text": "${icon} Local Backup ${status}",
    "attachments": [{
        "color": "${color}",
        "fields": [
            {"title": "Host", "value": "$(hostname)", "short": true},
            {"title": "Environment", "value": "${ENV}", "short": true},
            {"title": "Details", "value": "${message}", "short": false}
        ]
    }]
}
PAYLOAD
        )
        curl -sf -X POST -H 'Content-Type: application/json' -d "$payload" "$ALERT_WEBHOOK_URL" --max-time 10 >/dev/null 2>&1 || true
    fi
}

cleanup() {
    local exit_code=$?
    if (( exit_code != 0 )); then
        echo "❌ Script terminated unexpectedly (exit code: $exit_code)" | tee -a "$LOG_FILE"
        send_alert "FAILURE" "Local backup script terminated unexpectedly with exit code $exit_code"
    fi
    exit "$exit_code"
}
trap cleanup EXIT
trap 'echo "⚠ Received SIGINT..."; exit 130' INT
trap 'echo "⚠ Received SIGTERM..."; exit 143' TERM

# ═══════════════════════════════════════════════════════════════
#  Execution
# ═══════════════════════════════════════════════════════════════

echo "═══════════════════════════════════════════════════" | tee -a "$LOG_FILE"
echo "  $(date '+%Y-%m-%d %H:%M:%S') — STARTING BACKUPS ($ENV)" | tee -a "$LOG_FILE"
echo "═══════════════════════════════════════════════════" | tee -a "$LOG_FILE"

SERVICES=("postgres" "rabbitmq" "meilisearch")

for SERVICE in "${SERVICES[@]}"; do
    echo "📦 Backing up ${SERVICE}..." | tee -a "$LOG_FILE"
    
    svc_start=$(date +%s)
    
    if make -C "${INFRA_DIR}/services/${SERVICE}" backup ENV="$ENV" >> "$LOG_FILE" 2>&1; then
        svc_end=$(date +%s)
        elapsed=$(( svc_end - svc_start ))
        human_time=$(printf '%dm%02ds' $((elapsed / 60)) $((elapsed % 60)))
        
        echo "✅ SUCCESS: ${SERVICE} backup (${human_time})" | tee -a "$LOG_FILE"
        SERVICE_RESULTS["$SERVICE"]="SUCCESS (${human_time})"
        TOTAL_BACKED_UP=$(( TOTAL_BACKED_UP + 1 ))
    else
        svc_end=$(date +%s)
        elapsed=$(( svc_end - svc_start ))
        human_time=$(printf '%dm%02ds' $((elapsed / 60)) $((elapsed % 60)))
        
        echo "❌ FAILED: ${SERVICE} backup (${human_time})" | tee -a "$LOG_FILE"
        SERVICE_RESULTS["$SERVICE"]="FAILED (${human_time})"
        TOTAL_FAILED=$(( TOTAL_FAILED + 1 ))
    fi
done

end_time=$(date +%s)
total_elapsed=$(( end_time - START_TIME ))
human_total=$(printf '%dm%02ds' $((total_elapsed / 60)) $((total_elapsed % 60)))

echo "═══════════════════════════════════════════════════" | tee -a "$LOG_FILE"
echo "  $(date '+%Y-%m-%d %H:%M:%S') — BACKUPS COMPLETED" | tee -a "$LOG_FILE"
echo "═══════════════════════════════════════════════════" | tee -a "$LOG_FILE"

# Prepare webhook payload message
webhook_msg="Environment: ${ENV}\n\nSERVICES:\n"
for service in "${SERVICES[@]}"; do
    webhook_msg+="— ${service}: ${SERVICE_RESULTS[$service]}\n"
done
webhook_msg+="\nSUMMARY:\nBacked Up: ${TOTAL_BACKED_UP} | Failed: ${TOTAL_FAILED}\nTotal Time: ${human_total}"

# Escape quotes just in case, to prevent broken JSON
webhook_msg="${webhook_msg//\"/\\\"}"

# Send alert on completion (success or failure)
# Disable trap because we handled it gracefully
trap - EXIT 

if (( TOTAL_FAILED > 0 )); then
    send_alert "FAILURE" "${webhook_msg}"
    exit 1
else
    send_alert "SUCCESS" "${webhook_msg}"
    exit 0
fi
