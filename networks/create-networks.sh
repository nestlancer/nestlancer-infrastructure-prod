#!/usr/bin/env bash
set -euo pipefail

# ═══════════════════════════════════════════════════════════════════
# CREATE NETWORKS — Creates gateway + internal networks for PROD
# Usage: ./create-networks.sh
# ═══════════════════════════════════════════════════════════════════

ENV="prod"

# ── Subnet Definitions (PROD only) ──
GATEWAY_SUBNET="172.22.0.0/24"
PG_SUBNET="172.22.1.0/28"
RC_SUBNET="172.22.2.0/28"
RP_SUBNET="172.22.3.0/28"
RMQ_SUBNET="172.22.4.0/28"
MEILI_SUBNET="172.22.5.0/28"
CLAM_SUBNET="172.22.6.0/28"

create_network() {
    local name="$1"
    local subnet="$2"
    local internal="${3:-false}"

    if docker network inspect "$name" >/dev/null 2>&1; then
        echo "  ⏭️  Network '$name' already exists — skipping"
        return 0
    fi

    local cmd="docker network create --driver bridge --subnet=$subnet"
    if [[ "$internal" == "true" ]]; then
        cmd="$cmd --internal"
    fi
    cmd="$cmd $name"

    eval "$cmd"
    echo "  ✅ Created network '$name' (subnet: $subnet)"
}

echo "═══════════════════════════════════════════════════"
echo "  Creating networks for: ${ENV^^}"
echo "═══════════════════════════════════════════════════"

# Gateway network
create_network "gateway_${ENV}_network" "$GATEWAY_SUBNET" "false"

# Internal networks
create_network "pg_internal_${ENV}" "$PG_SUBNET" "true"
create_network "rc_internal_${ENV}" "$RC_SUBNET" "true"
create_network "rp_internal_${ENV}" "$RP_SUBNET" "true"
create_network "rmq_internal_${ENV}" "$RMQ_SUBNET" "true"
create_network "meili_internal_${ENV}" "$MEILI_SUBNET" "true"
create_network "clam_internal_${ENV}" "$CLAM_SUBNET" "true"

echo ""
echo "✅ All networks for ${ENV^^} created successfully"
