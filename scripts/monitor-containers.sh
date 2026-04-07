#!/usr/bin/env bash
set -euo pipefail

# =============================================
# Container Resource Monitor – Improved Version
# =============================================

# Defaults (reports/ lives at repository root, next to scripts/)
_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_REPO_ROOT="$(dirname "$_SCRIPT_DIR")"
DURATION=60
INTERVAL=2
CONTAINERS_CSV=""
OUT_DIR="${_REPO_ROOT}/reports"
OUTPUT_FORMAT="markdown"   # or "json"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
OUT_FILE=""
CLEANUP_FILES=()

# ---------------------------
# Helper functions
# ---------------------------
log_info()  { echo "[INFO]  $*" >&2; }
log_warn()  { echo "[WARN]  $*" >&2; }
log_error() { echo "[ERROR] $*" >&2; }

usage() {
    cat <<'EOF'
Usage: monitor-containers.sh [options]

Options:
  --duration <seconds>      Total monitor duration (default: 60)
  --interval <seconds>      Sampling interval (default: 2)
  --containers <a,b,c>      Comma-separated container names (default: all running)
  --out-dir <path>          Output directory (default: reports/ under repo root)
  --format <markdown|json>  Output format (default: markdown)
  -h, --help                Show help
EOF
}

cleanup() {
    if [[ ${#CLEANUP_FILES[@]} -gt 0 ]]; then
        rm -f "${CLEANUP_FILES[@]}"
    fi
}
trap cleanup EXIT INT TERM

# ---------------------------
# Parse arguments
# ---------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --duration)
            DURATION="$2"
            shift 2
            ;;
        --interval)
            INTERVAL="$2"
            shift 2
            ;;
        --containers)
            CONTAINERS_CSV="$2"
            shift 2
            ;;
        --out-dir)
            OUT_DIR="$2"
            shift 2
            ;;
        --format)
            OUTPUT_FORMAT="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Validate required commands
for cmd in docker awk mktemp; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        log_error "Required command '$cmd' not found."
        exit 1
    fi
done

# Validate numeric arguments
if ! [[ "$DURATION" =~ ^[0-9]+$ ]] || ! [[ "$INTERVAL" =~ ^[0-9]+$ ]] || [[ "$INTERVAL" -le 0 ]]; then
    log_error "--duration and --interval must be positive integers."
    exit 1
fi

# Validate output format
if [[ "$OUTPUT_FORMAT" != "markdown" && "$OUTPUT_FORMAT" != "json" ]]; then
    log_error "Invalid --format. Use 'markdown' or 'json'."
    exit 1
fi

# Determine target containers
if [[ -n "$CONTAINERS_CSV" ]]; then
    IFS=',' read -r -a TARGET_CONTAINERS <<<"$CONTAINERS_CSV"
else
    mapfile -t TARGET_CONTAINERS < <(docker ps --format '{{.Names}}')
fi

if [[ "${#TARGET_CONTAINERS[@]}" -eq 0 ]]; then
    log_error "No running containers found."
    exit 1
fi

mkdir -p "$OUT_DIR"
OUT_FILE="${OUT_DIR}/container-resource-report-${TIMESTAMP}.${OUTPUT_FORMAT}"

# ---------------------------
# Access check (concurrent)
# ---------------------------
ACCESS_FILE="$(mktemp)"
CLEANUP_FILES+=("$ACCESS_FILE")

log_info "Running concurrent access checks on ${#TARGET_CONTAINERS[@]} container(s)..."

check_container() {
    local c="$1"
    if docker exec "$c" sh -c 'true' 2>/dev/null; then
        echo "ACCESS_OK|$c|exec:sh"
    elif docker exec "$c" bash -c 'true' 2>/dev/null; then
        echo "ACCESS_OK|$c|exec:bash"
    elif docker inspect "$c" >/dev/null 2>&1; then
        echo "ACCESS_WARN|$c|inspect-only"
    else
        echo "ACCESS_FAIL|$c|unreachable"
    fi
}

for c in "${TARGET_CONTAINERS[@]}"; do
    check_container "$c" >> "$ACCESS_FILE" &
done
wait

log_info "Access check results:"
while IFS= read -r line; do
    log_info "  $line"
done < "$ACCESS_FILE"

# ---------------------------
# Sampling
# ---------------------------
SAMPLES_FILE="$(mktemp)"
CLEANUP_FILES+=("$SAMPLES_FILE")

SAMPLE_COUNT=$(( DURATION / INTERVAL ))
[[ "$SAMPLE_COUNT" -lt 1 ]] && SAMPLE_COUNT=1

log_info "Collecting $SAMPLE_COUNT samples (every ${INTERVAL}s for ${DURATION}s)..."

for ((i=1; i<=SAMPLE_COUNT; i++)); do
    TS="$(date +%s)"
    # Query only target containers directly so we always get expected rows.
    docker stats --no-stream \
        --format '{{.Name}}|{{.CPUPerc}}|{{.MemUsage}}|{{.MemPerc}}|{{.NetIO}}|{{.BlockIO}}|{{.PIDs}}' \
        "${TARGET_CONTAINERS[@]}" 2>/dev/null \
        | sed "s/^/${TS}|/" >> "$SAMPLES_FILE" || true
    # If stats fails temporarily, continue remaining samples.
    if [[ "$i" -lt "$SAMPLE_COUNT" ]]; then
        sleep "$INTERVAL"
    fi
done

# Count how many samples we actually got per container
log_info "Sampling completed. Generating report..."

# ---------------------------
# Report generation (AWK)
# ---------------------------
if [[ "$OUTPUT_FORMAT" == "markdown" ]]; then
    cat > "$OUT_FILE" <<EOF
# Container Resource Report

- **Monitoring period:** ${DURATION} seconds
- **Sampling interval:** ${INTERVAL} seconds
- **Samples collected:** $SAMPLE_COUNT
- **Timestamp:** $TIMESTAMP
- **Containers monitored:** ${TARGET_CONTAINERS[*]}

EOF
fi

# Common AWK script for data processing (used for both markdown and JSON)
AWK_SCRIPT='
function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }

function to_bytes(v) {
    v = trim(v)
    if (v == "" || v == "--" || v == "0B" || v == "0") return 0
    if (match(v, /^([0-9.]+)[[:space:]]*([A-Za-z]+)$/, m)) {
        n = m[1] + 0
        unit = m[2]
    } else {
        return v + 0
    }
    if (unit == "B") return n
    if (unit == "kB" || unit == "KB") return n * 1000
    if (unit == "MB") return n * 1000 * 1000
    if (unit == "GB") return n * 1000 * 1000 * 1000
    if (unit == "TB") return n * 1000 * 1000 * 1000 * 1000
    if (unit == "KiB") return n * 1024
    if (unit == "MiB") return n * 1024 * 1024
    if (unit == "GiB") return n * 1024 * 1024 * 1024
    if (unit == "TiB") return n * 1024 * 1024 * 1024 * 1024
    return n
}

function fmt_bytes(b) {
    if (b >= 1024*1024*1024) return sprintf("%.2f GiB", b/(1024*1024*1024))
    if (b >= 1024*1024) return sprintf("%.2f MiB", b/(1024*1024))
    if (b >= 1024) return sprintf("%.2f KiB", b/1024)
    return sprintf("%.0f B", b)
}

{
    ts = $1
    name = trim($2)
    cpu = trim($3); gsub(/%/, "", cpu); if (cpu == "" || cpu == "--") cpu = 0
    mem_usage = trim($4)
    mem_pct = trim($5); gsub(/%/, "", mem_pct); if (mem_pct == "" || mem_pct == "--") mem_pct = 0
    netio = trim($6)
    blkio = trim($7)

    split(mem_usage, mm, "/")
    mem_used_b = to_bytes(trim(mm[1]))

    split(netio, nn, "/")
    net_rx_b = to_bytes(trim(nn[1]))
    net_tx_b = to_bytes(trim(nn[2]))

    split(blkio, bb, "/")
    blk_r_b = to_bytes(trim(bb[1]))
    blk_w_b = to_bytes(trim(bb[2]))

    count[name]++
    cpu_sum[name] += cpu
    mem_pct_sum[name] += mem_pct
    mem_sum_b[name] += mem_used_b
    if (cpu > cpu_peak[name]) cpu_peak[name] = cpu
    if (mem_pct > mem_pct_peak[name]) mem_pct_peak[name] = mem_pct
    if (mem_used_b > mem_peak_b[name]) mem_peak_b[name] = mem_used_b

    if (!(name in first_rx_b)) {
        first_rx_b[name] = net_rx_b
        first_tx_b[name] = net_tx_b
        first_blk_r_b[name] = blk_r_b
        first_blk_w_b[name] = blk_w_b
    }
    last_rx_b[name] = net_rx_b
    last_tx_b[name] = net_tx_b
    last_blk_r_b[name] = blk_r_b
    last_blk_w_b[name] = blk_w_b
}

END {
    # Prepare data
    for (n in count) {
        avg_cpu = cpu_sum[n] / count[n]
        avg_mem_pct = mem_pct_sum[n] / count[n]
        avg_mem_b = mem_sum_b[n] / count[n]

        net_rx_delta = last_rx_b[n] - first_rx_b[n]
        net_tx_delta = last_tx_b[n] - first_tx_b[n]
        blk_r_delta = last_blk_r_b[n] - first_blk_r_b[n]
        blk_w_delta = last_blk_w_b[n] - first_blk_w_b[n]

        # Prevent negative values (e.g., on counter reset)
        if (net_rx_delta < 0) net_rx_delta = 0
        if (net_tx_delta < 0) net_tx_delta = 0
        if (blk_r_delta < 0) blk_r_delta = 0
        if (blk_w_delta < 0) blk_w_delta = 0

        # Store for later output
        name_list[++i] = n
        samples[i] = count[n]
        avg_cpu_arr[i] = avg_cpu
        peak_cpu_arr[i] = cpu_peak[n]
        avg_mem_arr[i] = avg_mem_b
        peak_mem_arr[i] = mem_peak_b[n]
        avg_mem_pct_arr[i] = avg_mem_pct
        peak_mem_pct_arr[i] = mem_pct_peak[n]
        net_rx_arr[i] = net_rx_delta
        net_tx_arr[i] = net_tx_delta
        blk_r_arr[i] = blk_r_delta
        blk_w_arr[i] = blk_w_delta
    }

    # Output in requested format
    if (fmt == "markdown") {
        print "| Container | Samples | Avg CPU % | Peak CPU % | Avg Mem | Peak Mem | Avg Mem % | Peak Mem % | Net RX (window) | Net TX (window) | Block Read (window) | Block Write (window) |"
        print "|:---|:---:|---:|---:|:---|:---:|---:|---:|:---|:---|:---|:---|"
        for (j = 1; j <= i; j++) {
            printf("| %s | %d | %.2f | %.2f | %s | %s | %.2f | %.2f | %s | %s | %s | %s |\n",
                name_list[j], samples[j],
                avg_cpu_arr[j], peak_cpu_arr[j],
                fmt_bytes(avg_mem_arr[j]), fmt_bytes(peak_mem_arr[j]),
                avg_mem_pct_arr[j], peak_mem_pct_arr[j],
                fmt_bytes(net_rx_arr[j]), fmt_bytes(net_tx_arr[j]),
                fmt_bytes(blk_r_arr[j]), fmt_bytes(blk_w_arr[j]))
        }
    } else if (fmt == "json") {
        printf "{\n  \"containers\": [\n"
        for (j = 1; j <= i; j++) {
            printf "    {\n"
            printf "      \"name\": \"%s\",\n", name_list[j]
            printf "      \"samples\": %d,\n", samples[j]
            printf "      \"cpu\": { \"avg\": %.2f, \"peak\": %.2f },\n", avg_cpu_arr[j], peak_cpu_arr[j]
            printf "      \"memory\": {\n"
            printf "        \"avg_bytes\": %.0f,\n", avg_mem_arr[j]
            printf "        \"peak_bytes\": %.0f,\n", peak_mem_arr[j]
            printf "        \"avg_percent\": %.2f,\n", avg_mem_pct_arr[j]
            printf "        \"peak_percent\": %.2f\n", peak_mem_pct_arr[j]
            printf "      },\n"
            printf "      \"network\": {\n"
            printf "        \"rx_bytes\": %.0f,\n", net_rx_arr[j]
            printf "        \"tx_bytes\": %.0f\n", net_tx_arr[j]
            printf "      },\n"
            printf "      \"block_io\": {\n"
            printf "        \"read_bytes\": %.0f,\n", blk_r_arr[j]
            printf "        \"write_bytes\": %.0f\n", blk_w_arr[j]
            printf "      }\n"
            printf "    }%s\n", (j == i ? "" : ",")
        }
        printf "  ]\n}\n"
    }
}
'

# Run AWK with the chosen format
awk -v fmt="$OUTPUT_FORMAT" -F'|' "$AWK_SCRIPT" "$SAMPLES_FILE" >> "$OUT_FILE"

# For JSON, also add metadata manually (since AWK script only writes container data)
if [[ "$OUTPUT_FORMAT" == "json" ]]; then
    # We need to insert metadata at the top. Use temporary file.
    TMP_JSON="$(mktemp)"
    CLEANUP_FILES+=("$TMP_JSON")
    {
        echo "{"
        echo "  \"timestamp\": \"$TIMESTAMP\","
        echo "  \"duration_seconds\": $DURATION,"
        echo "  \"interval_seconds\": $INTERVAL,"
        echo "  \"samples_expected\": $SAMPLE_COUNT,"
        # Remove the leading "{\n  \"containers\": [\n" from the existing file,
        # then append properly. This is a bit hacky but works.
        tail -n +2 "$OUT_FILE" | sed '1s/^  "containers":/  "containers":/'
    } > "$TMP_JSON"
    mv "$TMP_JSON" "$OUT_FILE"
fi

log_info "Report generated: $OUT_FILE"
if [[ "$OUTPUT_FORMAT" == "markdown" ]]; then
    cat "$OUT_FILE"
fi