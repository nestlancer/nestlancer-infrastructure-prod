#!/usr/bin/env bash
set -euo pipefail

# ═══════════════════════════════════════════════════════════════
# Tailscale Subnet Router Helper (Automated)
# Identifies Docker subnets to advertise for cross-machine access
# ═══════════════════════════════════════════════════════════════

RUN_AUTOMATED=false
if [[ "${1:-}" == "--run" ]]; then
    RUN_AUTOMATED=true
fi

# Check if Tailscale is installed
if ! command -v tailscale &> /dev/null; then
    echo "❌ Tailscale is not installed on this machine."
    echo "Please visit https://tailscale.com/download to install it."
    exit 1
fi

# Get the list of production Docker networks
NETWORKS=$(docker network ls --filter "name=prod" --format "{{.Name}}")

if [[ -z "$NETWORKS" ]]; then
    echo "❌ No production Docker networks found (expecting 'prod' in name)."
    exit 1
fi

echo "🔍 Identifying production subnets..."
SUBNETS=""
for net in $NETWORKS; do
    subnet=$(docker network inspect "$net" --format '{{range .IPAM.Config}}{{.Subnet}}{{end}}')
    if [[ -n "$subnet" ]]; then
        echo "   - $net: $subnet"
        if [[ -z "$SUBNETS" ]]; then
            SUBNETS="$subnet"
        else
            SUBNETS="$SUBNETS,$subnet"
        fi
    fi
done

echo ""
if [ "$RUN_AUTOMATED" = false ]; then
    echo "🚀 To advertise these routes via Tailscale, run this script with --run:"
    echo "----------------------------------------------------------------------"
    echo "./tailscale-setup.sh --run"
    echo "----------------------------------------------------------------------"
    echo ""
    echo "Or manually run:"
    echo "sudo tailscale up --advertise-routes=$SUBNETS --accept-routes"
    exit 0
fi

echo "🚀 Executing automated setup..."

# 1. Enable IP Forwarding
echo "── Enabling IP Forwarding..."
sudo sysctl -w net.ipv4.ip_forward=1
sudo sysctl -w net.ipv6.conf.all.forwarding=1

# 2. Advertise Routes
echo "── Advertising routes to Tailscale..."
sudo tailscale up --advertise-routes="$SUBNETS" --accept-routes

# 3. Fix Firewall (NFTables Raw Table)
if command -v nft >/dev/null 2>&1; then
    echo "── Checking for NFTables raw table restrictions..."
    if sudo nft list table ip raw &>/dev/null; then
        echo "   - Found 'ip raw' table. Inserting Tailscale exception at the top..."
        # Insert at the beginning of PREROUTING to ensure it precedes any drop rules
        sudo nft insert rule ip raw PREROUTING iifname "tailscale0" accept
    fi
fi

# 4. Fix Firewall (IPTables DOCKER-USER)
if command -v iptables >/dev/null 2>&1; then
    echo "── Checking for IPTables DOCKER-USER restrictions..."
    # Ensure Tailscale range 100.64.0.0/10 can reach containers
    sudo iptables -I DOCKER-USER -s 100.64.0.0/10 -j ACCEPT 2>/dev/null || true
    sudo iptables -I DOCKER-USER -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true
    # Masking for return traffic
    sudo iptables -t nat -I POSTROUTING -s 100.64.0.0/10 -j MASQUERADE 2>/dev/null || true
fi

echo ""
echo "✅ Automated setup complete!"
echo "----------------------------------------------------------------------"
echo "📝 FINAL STEPS REQUIRED:"
echo "1. Go to the Tailscale Admin Console (https://login.tailscale.com/admin/machines)."
echo "2. Find this machine, click the '...' menu, select 'Edit route settings'."
echo "3. Enable all the subnets you just advertised."
echo "----------------------------------------------------------------------"
echo ""
echo "🌐 Your other Tailscale machines can now access containers at their internal IPs."
echo "Current Machine Tailscale IP: $(tailscale ip -4)"
echo ""
echo "📱 Active Production Containers & IPs:"
echo "----------------------------------------------------------------------"
docker ps --filter "name=prod" --format "{{.Names}}" | while read name; do
    ips=$(docker inspect "$name" --format '{{range .NetworkSettings.Networks}}{{.IPAddress}} {{end}}')
    printf "   %-25s %s\n" "$name" "$ips"
done
echo "----------------------------------------------------------------------"
echo ""
echo "🧹 Maintenance:"
echo "To stop advertising ALL routes, run:"
echo "----------------------------------------------------------------------"
echo "sudo tailscale set --advertise-routes="
echo "----------------------------------------------------------------------"
