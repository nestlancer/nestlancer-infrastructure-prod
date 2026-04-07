#!/usr/bin/env bash
set -euo pipefail

# ═══════════════════════════════════════════════════════════════════════════
#  Cloud Sync — Professional Backup Upload to Backblaze B2
# ═══════════════════════════════════════════════════════════════════════════
#
#  Usage:
#    ./cloud-sync.sh                  # Normal sync
#    ./cloud-sync.sh --dry-run        # Preview without uploading
#    ./cloud-sync.sh --verbose        # Detailed output
#    ./cloud-sync.sh --quiet          # Minimal output (for cron)
#    ./cloud-sync.sh --cleanup        # Also purge old remote files
#    ./cloud-sync.sh --verify-only    # Only verify remote integrity
#    ./cloud-sync.sh --status         # Show remote storage stats
#    ./cloud-sync.sh --force          # Skip lock check
#
#  Requires: rclone >= 1.60 (https://rclone.org/)
# ═══════════════════════════════════════════════════════════════════════════

readonly SCRIPT_VERSION="2.0.0"
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly INFRA_DIR="$(dirname "$SCRIPTS_DIR")"
readonly LOG_FILE="${INFRA_DIR}/logs/cloud-sync.log"
readonly LOCK_FILE="/tmp/cloud-sync.lock"
readonly STATE_FILE="${INFRA_DIR}/.cloud-sync.state"

# ═══════════════════════════════════════════════════════════════
#  CONFIGURATION & CREDENTIALS
# ═══════════════════════════════════════════════════════════════

# ── Credentials ──
B2_ACCOUNT_ID="0035be8662d09360000000004"
B2_APPLICATION_KEY="K0034smpkYgxmsWh7yUwyo+FaOWz/jI"
ALERT_WEBHOOK_URL="https://discord.com/api/webhooks/1485114548414578839/4UeZC814A3zmUDg0XTD6T47GiIdMH81Zxx1JY_ctNBfvpR3JUyljTQ8ilduHk8buY970/slack"
# ALERT_EMAIL="ops@yourdomain.com"

# ── Remote Storage ──
REMOTE_BACKEND=":b2"
REMOTE_BUCKET="nl-infra-services-prod-backup"

# ── Local Paths ──
LOCAL_BACKUP_ROOT="/root/Desktop/docker-infra-data/prod"

# ── Sync Behavior ──
# "copy"  = upload new/changed files, never delete remote (SAFE)
# "sync"  = exact mirror, deletes remote files missing locally (DANGEROUS)
SYNC_MODE="copy"

# ── Services to Sync ──
# Format: "local_subpath:remote_folder_name"
SYNC_TARGETS=(
    "postgres/pg_backups:postgres"
    "rabbitmq/backups:rabbitmq"
    "meilisearch/meili_data/dumps:meilisearch"
)

# ── Performance ──
PARALLEL_TRANSFERS=4          # Concurrent file uploads
CHECKERS=8                    # Concurrent hash checkers
BANDWIDTH_LIMIT=""            # e.g., "10M" for 10MB/s (empty = unlimited)
CHUNK_SIZE="96M"              # B2 upload chunk size (96M optimal for B2)

# ── Reliability ──
MAX_RETRIES=3                 # Retry failed transfers
RETRY_BACKOFF="1s"            # Initial retry delay (doubles each retry)
LOW_LEVEL_RETRIES=10          # Retries for low-level failures (network drops)
TIMEOUT="60s"                 # Per-operation timeout
CONTIMEOUT="30s"              # Connection timeout

# ── Integrity ──
CHECKSUM_VERIFY=true          # Verify checksums after upload
SIZE_ONLY=false               # Use size-only comparison (faster, less safe)

# ── Retention (for remote cleanup — only used with --cleanup flag) ──
RETENTION_DAYS=90             # Delete remote files older than this

# ── Log Management ──
LOG_MAX_SIZE_MB=50            # Rotate log when it exceeds this size
LOG_KEEP_COUNT=5              # Number of rotated logs to keep

# ── Ensure log directory ──
mkdir -p "$(dirname "$LOG_FILE")"

# ═══════════════════════════════════════════════════════════════
#  Color & Formatting
# ═══════════════════════════════════════════════════════════════

if [[ -t 1 ]]; then
    readonly C_RED='\033[0;31m'
    readonly C_GREEN='\033[0;32m'
    readonly C_YELLOW='\033[0;33m'
    readonly C_BLUE='\033[0;34m'
    readonly C_CYAN='\033[0;36m'
    readonly C_DIM='\033[2m'
    readonly C_BOLD='\033[1m'
    readonly C_RESET='\033[0m'
else
    readonly C_RED='' C_GREEN='' C_YELLOW='' C_BLUE=''
    readonly C_CYAN='' C_DIM='' C_BOLD='' C_RESET=''
fi

# ═══════════════════════════════════════════════════════════════
#  Logging
# ═══════════════════════════════════════════════════════════════

VERBOSITY=1  # 0=quiet, 1=normal, 2=verbose

log() {
    local level="$1" msg="$2"
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    local log_line="${timestamp} [${level}] ${msg}"

    # Always write to log file
    echo "$log_line" >> "$LOG_FILE"

    # Console output based on verbosity
    case "$level" in
        ERROR)   [[ $VERBOSITY -ge 0 ]] && echo -e "${C_RED}✖ ERROR:${C_RESET} ${msg}" >&2 || true ;;
        WARN)    [[ $VERBOSITY -ge 1 ]] && echo -e "${C_YELLOW}⚠ WARN:${C_RESET}  ${msg}" || true ;;
        SUCCESS) [[ $VERBOSITY -ge 1 ]] && echo -e "${C_GREEN}✔ OK:${C_RESET}    ${msg}" || true ;;
        INFO)    [[ $VERBOSITY -ge 1 ]] && echo -e "${C_BLUE}ℹ INFO:${C_RESET}  ${msg}" || true ;;
        DEBUG)   [[ $VERBOSITY -ge 2 ]] && echo -e "${C_DIM}⋯ DEBUG: ${msg}${C_RESET}" || true ;;
        HEADER)  [[ $VERBOSITY -ge 0 ]] && echo -e "\n${C_BOLD}${C_CYAN}${msg}${C_RESET}" || true ;;
    esac
}

banner() {
    local msg="$1"
    local line="══════════════════════════════════════════════════════════"
    log HEADER "$line"
    log HEADER "  $msg"
    log HEADER "$line"
}

# ═══════════════════════════════════════════════════════════════
#  Log Rotation
# ═══════════════════════════════════════════════════════════════

rotate_logs() {
    local max_size_bytes=$(( ${LOG_MAX_SIZE_MB:-50} * 1024 * 1024 ))
    local keep=${LOG_KEEP_COUNT:-5}

    [[ ! -f "$LOG_FILE" ]] && return 0

    local current_size
    current_size=$(stat -f%z "$LOG_FILE" 2>/dev/null || stat -c%s "$LOG_FILE" 2>/dev/null || echo 0)

    if (( current_size > max_size_bytes )); then
        log DEBUG "Log file exceeds ${LOG_MAX_SIZE_MB}MB — rotating"

        # Shift existing rotated logs
        for (( i = keep - 1; i >= 1; i-- )); do
            local prev=$(( i - 1 ))
            [[ -f "${LOG_FILE}.${prev}.gz" ]] && mv "${LOG_FILE}.${prev}.gz" "${LOG_FILE}.${i}.gz"
        done

        # Compress current log
        gzip -c "$LOG_FILE" > "${LOG_FILE}.0.gz"
        : > "$LOG_FILE"

        log INFO "Log rotated successfully"
    fi
}

# ═══════════════════════════════════════════════════════════════
#  Lock Management (Prevent Concurrent Runs)
# ═══════════════════════════════════════════════════════════════

acquire_lock() {
    if [[ -f "$LOCK_FILE" ]]; then
        local lock_pid
        lock_pid=$(<"$LOCK_FILE")

        # Check if the process that created the lock is still running
        if kill -0 "$lock_pid" 2>/dev/null; then
            if [[ "$FORCE_MODE" == true ]]; then
                log WARN "Overriding existing lock (PID: $lock_pid) with --force"
                kill "$lock_pid" 2>/dev/null || true
                sleep 2
            else
                log ERROR "Another sync is already running (PID: $lock_pid)"
                log ERROR "Use --force to override, or remove $LOCK_FILE manually"
                exit 1
            fi
        else
            log WARN "Stale lock file found (PID: $lock_pid no longer running) — removing"
        fi
        rm -f "$LOCK_FILE"
    fi

    echo $$ > "$LOCK_FILE"
    log DEBUG "Lock acquired (PID: $$)"
}

release_lock() {
    rm -f "$LOCK_FILE"
    log DEBUG "Lock released"
}

# ═══════════════════════════════════════════════════════════════
#  Signal Handling & Cleanup
# ═══════════════════════════════════════════════════════════════

SYNC_START_TIME=""
TOTAL_SYNCED=0
TOTAL_FAILED=0
TOTAL_SKIPPED=0
declare -A SERVICE_RESULTS=()

cleanup() {
    local exit_code=$?
    release_lock

    if (( exit_code != 0 )); then
        log ERROR "Script terminated unexpectedly (exit code: $exit_code)"
        send_alert "FAILURE" "Cloud sync terminated with exit code $exit_code"
    fi

    exit "$exit_code"
}

trap cleanup EXIT
trap 'log WARN "Received SIGINT — shutting down gracefully..."; exit 130' INT
trap 'log WARN "Received SIGTERM — shutting down gracefully..."; exit 143' TERM

# ═══════════════════════════════════════════════════════════════
#  Alert / Notification System
# ═══════════════════════════════════════════════════════════════

send_alert() {
    local status="$1" message="$2"

    # Webhook alert (Slack/Discord/generic)
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
    "text": "${icon} Cloud Sync ${status}",
    "attachments": [{
        "color": "${color}",
        "fields": [
            {"title": "Host", "value": "$(hostname)", "short": true},
            {"title": "Time", "value": "$(date '+%Y-%m-%d %H:%M:%S')", "short": true},
            {"title": "Details", "value": "${message}", "short": false}
        ]
    }]
}
PAYLOAD
        )

        curl -sf -X POST \
            -H 'Content-Type: application/json' \
            -d "$payload" \
            "$ALERT_WEBHOOK_URL" \
            --max-time 10 \
            >/dev/null 2>&1 || log WARN "Failed to send webhook alert"

        log DEBUG "Webhook alert sent"
    fi

    # Email alert
    if [[ -n "${ALERT_EMAIL:-}" ]] && command -v mail &>/dev/null; then
        echo "$message" | mail -s "[Cloud Sync] ${status} on $(hostname)" "$ALERT_EMAIL" \
            || log WARN "Failed to send email alert"
        log DEBUG "Email alert sent to $ALERT_EMAIL"
    fi
}

# ═══════════════════════════════════════════════════════════════
#  Preflight Checks
# ═══════════════════════════════════════════════════════════════

preflight_checks() {
    log INFO "Running preflight checks..."
    local errors=0

    # 1) rclone installed
    if ! command -v rclone &>/dev/null; then
        log ERROR "rclone is not installed — https://rclone.org/install/"
        (( errors++ ))
    else
        local rclone_version
        rclone_version=$(rclone version --check 2>/dev/null | head -1 || rclone version 2>/dev/null | head -1)
        log DEBUG "rclone: $rclone_version"
    fi

    # 2) Backup root exists
    if [[ ! -d "$LOCAL_BACKUP_ROOT" ]]; then
        log ERROR "Local backup root does not exist: $LOCAL_BACKUP_ROOT"
        (( errors++ ))
    fi

    # 5) Required credentials are set
    if [[ -z "${B2_ACCOUNT_ID:-}" || -z "${B2_APPLICATION_KEY:-}" ]]; then
        log ERROR "B2 credentials are missing or empty"
        (( errors++ ))
    fi

    # 6) Validate each sync target directory
    for target in "${SYNC_TARGETS[@]}"; do
        local local_path="${target%%:*}"
        local full_path="${LOCAL_BACKUP_ROOT}/${local_path}"
        if [[ ! -d "$full_path" ]]; then
            log WARN "Sync target directory missing: $full_path — will be skipped"
        fi
    done

    # 7) Test B2 connectivity
    if (( errors == 0 )); then
        log DEBUG "Testing B2 connectivity..."
        if ! rclone lsd "${REMOTE_BACKEND}:${REMOTE_BUCKET}" \
            --b2-account "$B2_ACCOUNT_ID" \
            --b2-key "$B2_APPLICATION_KEY" \
            --contimeout "${CONTIMEOUT:-30s}" \
            >/dev/null 2>&1; then
            log ERROR "Cannot connect to B2 bucket '${REMOTE_BUCKET}' — check credentials and bucket name"
            (( errors++ ))
        else
            log SUCCESS "B2 connectivity verified"
        fi
    fi

    if (( errors > 0 )); then
        log ERROR "Preflight failed with $errors error(s) — aborting"
        exit 1
    fi

    log SUCCESS "All preflight checks passed"
}

# ═══════════════════════════════════════════════════════════════
#  Build rclone Flags
# ═══════════════════════════════════════════════════════════════

build_rclone_flags() {
    local -a flags=()

    # B2 credentials
    flags+=(--b2-account "$B2_ACCOUNT_ID")
    flags+=(--b2-key "$B2_APPLICATION_KEY")

    # Performance
    flags+=(--transfers "${PARALLEL_TRANSFERS:-4}")
    flags+=(--checkers "${CHECKERS:-8}")
    flags+=(--b2-chunk-size "${CHUNK_SIZE:-96Mi}")
    flags+=(--fast-list)

    # Bandwidth limit
    [[ -n "${BANDWIDTH_LIMIT:-}" ]] && flags+=(--bwlimit "$BANDWIDTH_LIMIT")

    # Reliability
    flags+=(--retries "${MAX_RETRIES:-3}")
    flags+=(--retries-sleep "${RETRY_BACKOFF:-1s}")
    flags+=(--low-level-retries "${LOW_LEVEL_RETRIES:-10}")
    flags+=(--timeout "${TIMEOUT:-60s}")
    flags+=(--contimeout "${CONTIMEOUT:-30s}")

    # Integrity
    if [[ "${SIZE_ONLY:-false}" == true ]]; then
        flags+=(--size-only)
    fi

    # Logging
    if (( VERBOSITY >= 2 )); then
        flags+=(-vv)
        flags+=(--stats 5s)
        flags+=(--stats-one-line)
    elif (( VERBOSITY >= 1 )); then
        flags+=(-v)
        flags+=(--stats 15s)
        flags+=(--stats-one-line)
    else
        flags+=(--stats 0)
    fi

    # Log rclone output to its own file
    flags+=(--log-file "${INFRA_DIR}/logs/rclone-detail.log")

    # Dry-run
    [[ "$DRY_RUN" == true ]] && flags+=(--dry-run)

    echo "${flags[@]}"
}

# ═══════════════════════════════════════════════════════════════
#  Sync a Single Service
# ═══════════════════════════════════════════════════════════════

sync_service() {
    local local_subpath="$1"
    local remote_name="$2"
    local source_path="${LOCAL_BACKUP_ROOT}/${local_subpath}"
    local dest_path="${REMOTE_BACKEND}:${REMOTE_BUCKET}/${remote_name}"

    # Check if source exists
    if [[ ! -d "$source_path" ]]; then
        log WARN "${remote_name}: source directory missing — skipping"
        SERVICE_RESULTS["$remote_name"]="SKIPPED"
        (( TOTAL_SKIPPED++ ))
        return 0
    fi

    # Count local files
    local local_count
    local_count=$(find "$source_path" -type f 2>/dev/null | wc -l)
    log INFO "${remote_name}: found ${local_count} local file(s) in ${local_subpath}"

    if (( local_count == 0 )); then
        log WARN "${remote_name}: no files to sync — skipping"
        SERVICE_RESULTS["$remote_name"]="SKIPPED (empty)"
        (( TOTAL_SKIPPED++ ))
        return 0
    fi

    # Calculate local size
    local local_size
    local_size=$(du -sh "$source_path" 2>/dev/null | cut -f1)
    log INFO "${remote_name}: local size is ${local_size}"

    # Build flags
    local -a rclone_flags
    read -ra rclone_flags <<< "$(build_rclone_flags)"

    # Execute sync
    local sync_start
    sync_start=$(date +%s)

    log INFO "${remote_name}: starting ${SYNC_MODE} → ${dest_path}"

    local sync_output
    if sync_output=$(rclone "$SYNC_MODE" "$source_path" "$dest_path" "${rclone_flags[@]}" 2>&1); then
        local sync_end elapsed
        sync_end=$(date +%s)
        elapsed=$(( sync_end - sync_start ))
        local human_time
        human_time=$(printf '%dm%02ds' $((elapsed / 60)) $((elapsed % 60)))

        log SUCCESS "${remote_name}: completed in ${human_time}"

        # Post-sync verification
        if [[ "${CHECKSUM_VERIFY:-true}" == true && "$DRY_RUN" != true ]]; then
            verify_service "$source_path" "$dest_path" "$remote_name"
        fi

        SERVICE_RESULTS["$remote_name"]="SUCCESS (${human_time}) [${local_count} files, ${local_size}]"
        (( TOTAL_SYNCED++ ))
        return 0
    else
        log ERROR "${remote_name}: sync failed"
        log ERROR "${remote_name}: ${sync_output}"
        SERVICE_RESULTS["$remote_name"]="FAILED"
        (( TOTAL_FAILED++ ))
        return 1
    fi
}

# ═══════════════════════════════════════════════════════════════
#  Integrity Verification
# ═══════════════════════════════════════════════════════════════

verify_service() {
    local source_path="$1" dest_path="$2" service_name="$3"

    log INFO "${service_name}: verifying integrity..."

    local check_output
    if check_output=$(rclone check "$source_path" "$dest_path" \
        --b2-account "$B2_ACCOUNT_ID" \
        --b2-key "$B2_APPLICATION_KEY" \
        --fast-list \
        --one-way \
        2>&1); then
        log SUCCESS "${service_name}: integrity verified ✔"
    else
        log WARN "${service_name}: integrity check reported differences"
        log DEBUG "${service_name}: $check_output"
    fi
}

# ═══════════════════════════════════════════════════════════════
#  Remote Cleanup (Retention Policy)
# ═══════════════════════════════════════════════════════════════

cleanup_remote() {
    local days="${RETENTION_DAYS:-90}"
    log INFO "Cleaning up remote files older than ${days} days..."

    for target in "${SYNC_TARGETS[@]}"; do
        local remote_name="${target##*:}"
        local dest_path="${REMOTE_BACKEND}:${REMOTE_BUCKET}/${remote_name}"

        log INFO "${remote_name}: scanning for files older than ${days} days..."

        local delete_flags=(
            --b2-account "$B2_ACCOUNT_ID"
            --b2-key "$B2_APPLICATION_KEY"
            --min-age "${days}d"
            --fast-list
        )
        [[ "$DRY_RUN" == true ]] && delete_flags+=(--dry-run)

        if rclone delete "$dest_path" "${delete_flags[@]}" 2>&1; then
            log SUCCESS "${remote_name}: cleanup completed"
        else
            log WARN "${remote_name}: cleanup encountered issues"
        fi
    done
}

# ═══════════════════════════════════════════════════════════════
#  Remote Status / Stats
# ═══════════════════════════════════════════════════════════════

show_status() {
    banner "REMOTE STORAGE STATUS"

    for target in "${SYNC_TARGETS[@]}"; do
        local remote_name="${target##*:}"
        local dest_path="${REMOTE_BACKEND}:${REMOTE_BUCKET}/${remote_name}"

        echo ""
        log INFO "━━━ ${remote_name} ━━━"

        local remote_size remote_count
        remote_size=$(rclone size "$dest_path" \
            --b2-account "$B2_ACCOUNT_ID" \
            --b2-key "$B2_APPLICATION_KEY" \
            --fast-list \
            --json 2>/dev/null)

        if [[ -n "$remote_size" ]]; then
            local count bytes
            count=$(echo "$remote_size" | grep -o '"count":[0-9]*' | grep -o '[0-9]*')
            bytes=$(echo "$remote_size" | grep -o '"bytes":[0-9]*' | grep -o '[0-9]*')
            local human_size
            human_size=$(numfmt --to=iec-i --suffix=B "$bytes" 2>/dev/null || echo "${bytes} bytes")
            log INFO "  Files: ${count}"
            log INFO "  Size:  ${human_size}"
        else
            log WARN "  Could not retrieve stats"
        fi

        # Show newest and oldest files
        local newest oldest
        newest=$(rclone lsl "$dest_path" \
            --b2-account "$B2_ACCOUNT_ID" \
            --b2-key "$B2_APPLICATION_KEY" \
            --fast-list 2>/dev/null | sort -k2,3 | tail -1 | awk '{print $2, $3, $4}')
        oldest=$(rclone lsl "$dest_path" \
            --b2-account "$B2_ACCOUNT_ID" \
            --b2-key "$B2_APPLICATION_KEY" \
            --fast-list 2>/dev/null | sort -k2,3 | head -1 | awk '{print $2, $3, $4}')

        [[ -n "$newest" ]] && log INFO "  Newest: ${newest}"
        [[ -n "$oldest" ]] && log INFO "  Oldest: ${oldest}"
    done

    echo ""
}

# ═══════════════════════════════════════════════════════════════
#  Print Summary Report
# ═══════════════════════════════════════════════════════════════

print_summary() {
    local end_time
    end_time=$(date +%s)
    local total_elapsed=$(( end_time - SYNC_START_TIME ))
    local human_total
    human_total=$(printf '%dm%02ds' $((total_elapsed / 60)) $((total_elapsed % 60)))

    echo ""
    banner "SYNC SUMMARY"
    echo ""

    printf "  ${C_BOLD}%-20s %-15s${C_RESET}\n" "SERVICE" "STATUS"
    printf "  %-20s %-15s\n" "────────────────────" "───────────────"

    for service in "${!SERVICE_RESULTS[@]}"; do
        local result="${SERVICE_RESULTS[$service]}"
        local color="$C_GREEN"
        [[ "$result" == *"FAILED"* ]] && color="$C_RED"
        [[ "$result" == *"SKIPPED"* ]] && color="$C_YELLOW"
        printf "  %-20s ${color}%-15s${C_RESET}\n" "$service" "$result"
    done

    echo ""
    printf "  ${C_DIM}Total time:     ${human_total}${C_RESET}\n"
    printf "  ${C_DIM}Mode:           ${SYNC_MODE}${C_RESET}\n"
    printf "  ${C_GREEN}Synced:         ${TOTAL_SYNCED}${C_RESET}\n"
    [[ $TOTAL_FAILED -gt 0 ]] && printf "  ${C_RED}Failed:         ${TOTAL_FAILED}${C_RESET}\n"
    [[ $TOTAL_SKIPPED -gt 0 ]] && printf "  ${C_YELLOW}Skipped:        ${TOTAL_SKIPPED}${C_RESET}\n"
    [[ "$DRY_RUN" == true ]] && printf "  ${C_YELLOW}⚠  DRY RUN — no files were transferred${C_RESET}\n"
    echo ""

    # Save state for monitoring
    cat > "$STATE_FILE" <<-STATE
LAST_RUN=$(date -Iseconds)
LAST_STATUS=$(( TOTAL_FAILED > 0 ? 1 : 0 ))
LAST_SYNCED=$TOTAL_SYNCED
LAST_FAILED=$TOTAL_FAILED
LAST_SKIPPED=$TOTAL_SKIPPED
LAST_DURATION=$total_elapsed
STATE

    # Prepare webhook payload message
    local webhook_msg="Mode: ${SYNC_MODE} | Dry Run: ${DRY_RUN}\n\nSERVICES:\n"
    for service in "${!SERVICE_RESULTS[@]}"; do
        webhook_msg+="— ${service}: ${SERVICE_RESULTS[$service]}\n"
    done
    webhook_msg+="\nSUMMARY:\nSynced: ${TOTAL_SYNCED} | Skipped: ${TOTAL_SKIPPED} | Failed: ${TOTAL_FAILED}\nTotal Time: ${human_total}"
    
    # Escape quotes just in case, to prevent broken JSON
    webhook_msg="${webhook_msg//\"/\\\"}"

    # Send alert on completion (success or failure)
    if (( TOTAL_FAILED > 0 )); then
        send_alert "FAILURE" "${webhook_msg}"
    else
        send_alert "SUCCESS" "${webhook_msg}"
    fi
}

# ═══════════════════════════════════════════════════════════════
#  Argument Parsing
# ═══════════════════════════════════════════════════════════════

DRY_RUN=false
FORCE_MODE=false
DO_CLEANUP=false
VERIFY_ONLY=false
SHOW_STATUS=false

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -n|--dry-run)
                DRY_RUN=true
                log DEBUG "Dry-run mode enabled"
                ;;
            -v|--verbose)
                VERBOSITY=2
                ;;
            -q|--quiet)
                VERBOSITY=0
                ;;
            -f|--force)
                FORCE_MODE=true
                ;;
            --cleanup)
                DO_CLEANUP=true
                ;;
            --verify-only)
                VERIFY_ONLY=true
                ;;
            --status)
                SHOW_STATUS=true
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            --version)
                echo "cloud-sync v${SCRIPT_VERSION}"
                exit 0
                ;;
            *)
                log ERROR "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
        shift
    done
}

show_help() {
    cat <<-HELP

  ${C_BOLD}cloud-sync v${SCRIPT_VERSION}${C_RESET} — Sync backups to Backblaze B2

  ${C_BOLD}USAGE${C_RESET}
    $SCRIPT_NAME [OPTIONS]

  ${C_BOLD}OPTIONS${C_RESET}
    -n, --dry-run        Preview sync without uploading anything
    -v, --verbose        Show detailed output and rclone stats
    -q, --quiet          Suppress console output (for cron jobs)
    -f, --force          Override lock file if another sync is stuck
        --cleanup        Also delete remote files older than retention period
        --verify-only    Only verify remote integrity, don't upload
        --status         Show remote storage statistics
    -h, --help           Show this help message
        --version        Show version

  ${C_BOLD}FILES${C_RESET}
    ${LOG_FILE}     Sync log

  ${C_BOLD}EXAMPLES${C_RESET}
    $SCRIPT_NAME                    # Normal sync
    $SCRIPT_NAME --dry-run -v       # Verbose dry-run preview
    $SCRIPT_NAME --quiet            # Cron-friendly quiet mode
    $SCRIPT_NAME --cleanup          # Sync + purge old remote files

HELP
}

# ═══════════════════════════════════════════════════════════════
#  MAIN EXECUTION
# ═══════════════════════════════════════════════════════════════

main() {
    parse_args "$@"

    # Export for rclone environment variable detection
    export RCLONE_B2_ACCOUNT="${B2_ACCOUNT_ID:-}"
    export RCLONE_B2_KEY="${B2_APPLICATION_KEY:-}"

    # Status mode — show stats and exit
    if [[ "$SHOW_STATUS" == true ]]; then
        show_status
        exit 0
    fi

    # Start
    banner "CLOUD SYNC v${SCRIPT_VERSION}  —  $(date '+%Y-%m-%d %H:%M:%S')"
    log INFO "Host: $(hostname) | Mode: ${SYNC_MODE:-copy} | Dry-run: ${DRY_RUN}"
    SYNC_START_TIME=$(date +%s)

    # Lock
    acquire_lock

    # Rotate logs if needed
    rotate_logs

    # Preflight
    preflight_checks

    # Verify-only mode
    if [[ "$VERIFY_ONLY" == true ]]; then
        log INFO "Running integrity verification only..."
        for target in "${SYNC_TARGETS[@]}"; do
            local local_subpath="${target%%:*}"
            local remote_name="${target##*:}"
            local source="${LOCAL_BACKUP_ROOT}/${local_subpath}"
            local dest="${REMOTE_BACKEND}:${REMOTE_BUCKET}/${remote_name}"
            [[ -d "$source" ]] && verify_service "$source" "$dest" "$remote_name"
        done
        print_summary
        exit 0
    fi

    # Main sync loop
    for target in "${SYNC_TARGETS[@]}"; do
        local local_subpath="${target%%:*}"
        local remote_name="${target##*:}"
        echo ""
        log INFO "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        sync_service "$local_subpath" "$remote_name" || true
    done

    # Cleanup old files if requested
    if [[ "$DO_CLEANUP" == true ]]; then
        echo ""
        cleanup_remote
    fi

    # Summary
    print_summary

    # Exit code based on failures
    if (( TOTAL_FAILED > 0 )); then
        exit 1
    fi
}

main "$@"
