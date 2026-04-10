#!/usr/bin/env bash
set -euo pipefail

# ═══════════════════════════════════════════════════════════════════════════
# Tailscale Subnet Router – Enterprise Automation (Setup & Removal)
# Advertises Docker container subnets with idempotent firewall adjustments,
# and provides a clean removal path for all modifications.
# ═══════════════════════════════════════════════════════════════════════════

readonly SCRIPT_NAME="$(basename "$0")"
readonly TAILSCALE_CIDR="100.64.0.0/10"

# Defaults
NETWORK_FILTER="prod"      # Docker network name filter
ENABLE_FIREWALL_FIX=true
DRY_RUN=false
LOG_LEVEL="INFO"           # DEBUG, INFO, WARN, ERROR

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# ═══════════════════════════════════════════════════════════════════════════
# Logging functions
# ═══════════════════════════════════════════════════════════════════════════
log() {
    local level="$1"; shift
    local color=""
    case "$level" in
        DEBUG) [[ "$LOG_LEVEL" == "DEBUG" ]] || return 0; color="$BLUE" ;;
        INFO)  color="$GREEN" ;;
        WARN)  color="$YELLOW" ;;
        ERROR) color="$RED" ;;
    esac
    echo -e "${color}[$(date +'%Y-%m-%d %H:%M:%S')] [$level] $*${NC}" >&2
}

die() {
    log ERROR "$@"
    exit 1
}

# ═══════════════════════════════════════════════════════════════════════════
# Usage
# ═══════════════════════════════════════════════════════════════════════════
usage() {
    cat <<EOF
Usage: $SCRIPT_NAME [OPTIONS]

Automatically advertise Docker container subnets via Tailscale and apply
necessary firewall adjustments, or cleanly remove all modifications.

Options:
  --run                  Apply changes (advertise subnets and fix firewall)
  --remove               Remove advertised routes and firewall exceptions
  --filter PATTERN       Docker network name filter (default: "prod")
  --no-firewall          Skip iptables/nftables modifications
  --debug                Enable debug logging
  -h, --help             Show this help

Examples:
  $SCRIPT_NAME --run                     # Advertise subnets
  $SCRIPT_NAME --remove                  # Stop advertising & clean firewall
  $SCRIPT_NAME --run --filter "prod|staging"
  $SCRIPT_NAME                            # Dry‑run preview of setup
  $SCRIPT_NAME --remove                   # Dry‑run preview of removal (use --run to apply)

EOF
    exit 0
}

# ═══════════════════════════════════════════════════════════════════════════
# Parse arguments
# ═══════════════════════════════════════════════════════════════════════════
RUN_APPLY=false
REMOVE_MODE=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --run)           RUN_APPLY=true ;;
        --remove)        REMOVE_MODE=true ;;
        --filter)        NETWORK_FILTER="$2"; shift ;;
        --no-firewall)   ENABLE_FIREWALL_FIX=false ;;
        --debug)         LOG_LEVEL="DEBUG" ;;
        -h|--help)       usage ;;
        *)               die "Unknown option: $1" ;;
    esac
    shift
done

# Determine dry‑run status
if [[ "$RUN_APPLY" == false ]]; then
    DRY_RUN=true
    if [[ "$REMOVE_MODE" == true ]]; then
        log INFO "Dry‑run mode – removal preview (use --run with --remove to execute)"
    else
        log INFO "Dry‑run mode – setup preview (use --run to execute)"
    fi
fi

# ═══════════════════════════════════════════════════════════════════════════
# Dependency checks
# ═══════════════════════════════════════════════════════════════════════════
for cmd in docker tailscale jq; do
    if ! command -v "$cmd" &>/dev/null; then
        die "$cmd is required but not installed."
    fi
done

# Ensure we can talk to Docker
if ! docker info &>/dev/null; then
    die "Cannot communicate with Docker daemon. Check permissions."
fi

# ═══════════════════════════════════════════════════════════════════════════
# Helper: Remove firewall rules (idempotent)
# ═══════════════════════════════════════════════════════════════════════════
remove_firewall_rules() {
    if [[ "$ENABLE_FIREWALL_FIX" != true ]]; then
        return 0
    fi

    log INFO "Removing firewall exceptions..."

    # NFTables raw table
    if command -v nft &>/dev/null && sudo nft list table ip raw &>/dev/null; then
        if sudo nft list chain ip raw PREROUTING 2>/dev/null | grep -q 'iifname "tailscale0" accept'; then
            log INFO "  Removing NFTables rule: accept tailscale0"
            # Find handle and delete (safer than deleting by content)
            handle=$(sudo nft -a list chain ip raw PREROUTING | grep 'iifname "tailscale0" accept' | awk '{print $NF}')
            if [[ -n "$handle" ]]; then
                sudo nft delete rule ip raw PREROUTING handle "$handle"
            fi
        fi
    fi

    # iptables DOCKER-USER chain
    if command -v iptables &>/dev/null; then
        # Remove ACCEPT for Tailscale CIDR (loop until none left)
        while sudo iptables -C DOCKER-USER -s "$TAILSCALE_CIDR" -j ACCEPT 2>/dev/null; do
            log INFO "  Removing iptables ACCEPT rule for $TAILSCALE_CIDR"
            sudo iptables -D DOCKER-USER -s "$TAILSCALE_CIDR" -j ACCEPT
        done

        # Remove RELATED,ESTABLISHED rule (only if it's the one we added; be cautious)
        while sudo iptables -C DOCKER-USER -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null; do
            log INFO "  Removing iptables RELATED,ESTABLISHED rule"
            sudo iptables -D DOCKER-USER -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
        done

        # Remove MASQUERADE rule
        while sudo iptables -t nat -C POSTROUTING -s "$TAILSCALE_CIDR" -j MASQUERADE 2>/dev/null; do
            log INFO "  Removing iptables MASQUERADE rule"
            sudo iptables -t nat -D POSTROUTING -s "$TAILSCALE_CIDR" -j MASQUERADE
        done
    fi
}

# ═══════════════════════════════════════════════════════════════════════════
# Removal mode main logic
# ═══════════════════════════════════════════════════════════════════════════
do_removal() {
    log WARN "Removing Tailscale advertised routes and firewall exceptions..."

    if [[ "$DRY_RUN" == true ]]; then
        log INFO "[DRY-RUN] Would execute: sudo tailscale set --advertise-routes="
        log INFO "[DRY-RUN] Would attempt to remove firewall rules."
        return 0
    fi

    # 1. Clear advertised routes
    log INFO "Clearing Tailscale advertised routes..."
    sudo tailscale set --advertise-routes=

    # 2. Remove firewall rules
    remove_firewall_rules

    log INFO "✅ Removal completed."
    echo ""
    echo "Note: IP forwarding settings (net.ipv4.ip_forward) are left unchanged."
    echo "To disable IP forwarding: sudo sysctl -w net.ipv4.ip_forward=0"
}

# ═══════════════════════════════════════════════════════════════════════════
# Setup mode main logic
# ═══════════════════════════════════════════════════════════════════════════
do_setup() {
    log INFO "Scanning Docker networks matching filter: '$NETWORK_FILTER'"
    mapfile -t networks < <(docker network ls --filter "name=$NETWORK_FILTER" --format '{{.Name}}')

    if [[ ${#networks[@]} -eq 0 ]]; then
        die "No Docker networks found matching filter."
    fi

    declare -a subnet_list=()
    for net in "${networks[@]}"; do
        # Use jq to safely extract all subnets (IPv4/IPv6)
        subnets=$(docker network inspect "$net" --format '{{json .IPAM.Config}}' | jq -r '.[].Subnet | select(. != null)')
        if [[ -n "$subnets" ]]; then
            while IFS= read -r subnet; do
                log INFO "  Found $net -> $subnet"
                subnet_list+=("$subnet")
            done <<< "$subnets"
        else
            log WARN "  No subnet defined for network $net"
        fi
    done

    if [[ ${#subnet_list[@]} -eq 0 ]]; then
        die "No subnets found to advertise."
    fi

    # Build comma‑separated list for Tailscale
    routes=$(IFS=,; echo "${subnet_list[*]}")
    log INFO "Subnets to advertise: $routes"

    # Determine Tailscale state (running or stopped)
    tailscale_status=$(tailscale status --json 2>/dev/null | jq -r '.BackendState // "Stopped"')
    log DEBUG "Tailscale backend state: $tailscale_status"

    if [[ "$tailscale_status" == "Running" ]]; then
        TAILSCALE_CMD="tailscale set"
    else
        TAILSCALE_CMD="tailscale up"
        log WARN "Tailscale not running – will perform initial 'tailscale up' (may require authentication)"
    fi

    if [[ "$DRY_RUN" == true ]]; then
        log INFO "[DRY-RUN] Would execute: sudo $TAILSCALE_CMD --advertise-routes=$routes --accept-routes"
        log INFO "[DRY-RUN] Would enable IP forwarding and apply firewall rules."
        return 0
    fi

    # -----------------------------------------------------------------------
    # 1. Enable IP forwarding
    # -----------------------------------------------------------------------
    log INFO "Enabling IP forwarding..."
    sudo sysctl -w net.ipv4.ip_forward=1 >/dev/null
    sudo sysctl -w net.ipv6.conf.all.forwarding=1 >/dev/null

    # -----------------------------------------------------------------------
    # 2. Advertise routes via Tailscale
    # -----------------------------------------------------------------------
    log INFO "Configuring Tailscale to advertise routes..."
    if [[ "$TAILSCALE_CMD" == "tailscale set" ]]; then
        sudo tailscale set --advertise-routes="$routes" --accept-routes
    else
        sudo tailscale up --advertise-routes="$routes" --accept-routes
    fi

    # -----------------------------------------------------------------------
    # 3. Firewall adjustments (idempotent)
    # -----------------------------------------------------------------------
    if [[ "$ENABLE_FIREWALL_FIX" == true ]]; then
        log INFO "Applying firewall exceptions..."

        # --- NFTables raw table (common on modern distributions) ---
        if command -v nft &>/dev/null && sudo nft list table ip raw &>/dev/null; then
            log DEBUG "NFTables 'ip raw' table detected"
            # Check if rule already exists
            if ! sudo nft list chain ip raw PREROUTING 2>/dev/null | grep -q 'iifname "tailscale0" accept'; then
                log INFO "  Inserting NFTables rule: accept tailscale0 in raw PREROUTING"
                sudo nft insert rule ip raw PREROUTING iifname "tailscale0" accept
            else
                log DEBUG "  NFTables rule already present"
            fi
        fi

        # --- iptables DOCKER-USER chain ---
        if command -v iptables &>/dev/null; then
            # ACCEPT from Tailscale CIDR
            if ! sudo iptables -C DOCKER-USER -s "$TAILSCALE_CIDR" -j ACCEPT 2>/dev/null; then
                log INFO "  Adding iptables DOCKER-USER ACCEPT for $TAILSCALE_CIDR"
                sudo iptables -I DOCKER-USER 1 -s "$TAILSCALE_CIDR" -j ACCEPT
            else
                log DEBUG "  iptables ACCEPT rule already exists"
            fi

            # ACCEPT established/related connections
            if ! sudo iptables -C DOCKER-USER -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null; then
                log INFO "  Adding iptables DOCKER-USER ACCEPT for RELATED,ESTABLISHED"
                sudo iptables -I DOCKER-USER 1 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
            else
                log DEBUG "  iptables RELATED,ESTABLISHED rule already exists"
            fi

            # MASQUERADE for return traffic
            if ! sudo iptables -t nat -C POSTROUTING -s "$TAILSCALE_CIDR" -j MASQUERADE 2>/dev/null; then
                log INFO "  Adding iptables MASQUERADE for $TAILSCALE_CIDR"
                sudo iptables -t nat -I POSTROUTING 1 -s "$TAILSCALE_CIDR" -j MASQUERADE
            else
                log DEBUG "  iptables MASQUERADE rule already exists"
            fi
        fi
    fi

    # -----------------------------------------------------------------------
    # Final status
    # -----------------------------------------------------------------------
    log INFO "✅ Configuration applied successfully."
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📋 NEXT STEPS (manual)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "1. Visit the Tailscale Admin Console: https://login.tailscale.com/admin/machines"
    echo "2. Locate this machine, click '...' → 'Edit route settings'"
    echo "3. Enable the subnets listed below:"
    printf "   • %s\n" "${subnet_list[@]}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    tailscale_ip=$(tailscale ip -4 2>/dev/null || echo "unknown")
    echo "🌐 This machine's Tailscale IP: $tailscale_ip"
    echo ""
    echo "📦 Active containers matching filter '$NETWORK_FILTER':"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    docker ps --filter "name=$NETWORK_FILTER" --format "{{.Names}}" | while read -r cname; do
        c_ip=$(docker inspect "$cname" --format '{{range .NetworkSettings.Networks}}{{.IPAddress}} {{end}}')
        printf "   %-30s %s\n" "$cname" "$c_ip"
    done
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "🛠️  To stop advertising all routes and clean up later, run:"
    echo "   $SCRIPT_NAME --remove --run"
}

# ═══════════════════════════════════════════════════════════════════════════
# Main dispatcher
# ═══════════════════════════════════════════════════════════════════════════
if [[ "$REMOVE_MODE" == true ]]; then
    do_removal
else
    do_setup
fi