#!/usr/bin/env bash
set -euo pipefail

# ═══════════════════════════════════════════════════════════════════
# LIST NETWORKS — Production Docker networks and their status
# Usage: ./list-networks.sh
# ═══════════════════════════════════════════════════════════════════

NETWORKS=(
    "gateway_prod_network"
    "pg_internal_prod"
    "rc_internal_prod"
    "rp_internal_prod"
    "rmq_internal_prod"
    "meili_internal_prod"
    "clam_internal_prod"
)

echo "╔═══════════════════════════════════════════════════════════════════╗"
echo "║              PRODUCTION NETWORK STATUS (nestlancer)               ║"
echo "╠════════════════════════════╦══════════╦══════════════════════════╣"
printf "║ %-26s ║ %-8s ║ %-24s ║\n" "NETWORK NAME" "STATUS" "SUBNET"
echo "╠════════════════════════════╬══════════╬══════════════════════════╣"

for net in "${NETWORKS[@]}"; do
    if docker network inspect "$net" >/dev/null 2>&1; then
        subnet=$(docker network inspect "$net" --format '{{range .IPAM.Config}}{{.Subnet}}{{end}}' 2>/dev/null || echo "N/A")
        printf "║ %-26s ║ %-8s ║ %-24s ║\n" "$net" "✅ UP" "$subnet"
    else
        printf "║ %-26s ║ %-8s ║ %-24s ║\n" "$net" "❌ DOWN" "—"
    fi
done

echo "╚════════════════════════════╩══════════╩══════════════════════════╝"
