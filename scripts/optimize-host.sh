#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# Infrastructure — Host Optimization Script (Post-Config)
# ═══════════════════════════════════════════════════════════════

# This script must be run on the DOCKER HOST as root.
# It tunes kernel parameters for high-performance DB/Cache workloads.

set -e

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root (use sudo)"
   exit 1
fi

echo "🚀 Starting Host Optimization..."

# 1. Memory Tuning
echo "── Tuning Memory (Swappiness & Dirty Ratios) ──"
sysctl -w vm.swappiness=10
sysctl -w vm.dirty_background_ratio=5
sysctl -w vm.dirty_ratio=15

# 2. Network Tuning
echo "── Tuning Network Sockets & IP Forwarding ──"
sysctl -w net.core.somaxconn=1024
sysctl -w net.ipv4.ip_forward=1
sysctl -w net.ipv6.conf.all.forwarding=1

# 3. Firewall (UFW) Tuning for Tailscale Subnet Routing
if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "active"; then
    echo "── Configuring UFW for Tailscale Subnet Routing ──"
    ufw route allow in on tailscale0
    ufw route allow out on tailscale0
fi

# 4. Docker IPTables Tuning for Tailscale
if command -v iptables >/dev/null 2>&1; then
    echo "── Configuring IPTables for Tailscale to Docker ──"
    # Allow Tailscale traffic to bypass Docker isolation
    iptables -I DOCKER-USER -s 100.64.0.0/10 -j ACCEPT
    iptables -I DOCKER-USER -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
    # Ensure masquerading for response traffic
    iptables -t nat -I POSTROUTING -s 100.64.0.0/10 -j MASQUERADE
fi

# 3. Transparent Huge Pages (Disable for Redis)
echo "── Disabling Transparent Huge Pages (THP) ──"
if [ -f /sys/kernel/mm/transparent_hugepage/enabled ]; then
    echo never > /sys/kernel/mm/transparent_hugepage/enabled
fi

# 4. Make changes permanent
echo "── Making changes permanent in /etc/sysctl.d/99-infra-prod.conf ──"
cat <<EOF > /etc/sysctl.d/99-infra-prod.conf
# Infrastructure Production Optimizations
vm.swappiness=10
vm.dirty_background_ratio=5
vm.dirty_ratio=15
net.core.somaxconn=1024
net.ipv4.ip_forward=1
net.ipv6.conf.all.forwarding=1
EOF

echo "✅ Host Optimization Complete!"
echo "Note: THP disablement may need a custom systemd unit or rc.local for persistence."
