#!/usr/bin/env bash
set -euo pipefail

# ═══════════════════════════════════════════════════════════════
# Redis Cache Custom Entrypoint — Config Merge Logic
# Merges base + environment-specific override config
# ═══════════════════════════════════════════════════════════════

CONFIG_DIR="/etc/redis"
FINAL_CONFIG="/tmp/redis-merged.conf"
rm -f "$FINAL_CONFIG"

echo "═══════════════════════════════════════════════════"
echo "  Redis Cache Custom Entrypoint"
echo "  Environment: ${APP_ENV:-prod}"
echo "═══════════════════════════════════════════════════"

# Merge base + override configs
# Redis uses the LAST occurrence of a directive
if [[ -f "$CONFIG_DIR/base.conf" ]]; then
    echo "==> Merging Redis configuration..."
    cat "$CONFIG_DIR/base.conf" > "$FINAL_CONFIG"
    echo "" >> "$FINAL_CONFIG"
    echo "# ═══ ENVIRONMENT OVERRIDES (${APP_ENV:-prod}) ═══" >> "$FINAL_CONFIG"
    if [[ -f "$CONFIG_DIR/override.conf" ]]; then
        cat "$CONFIG_DIR/override.conf" >> "$FINAL_CONFIG"
    fi
    echo "==> Redis configuration merged → $FINAL_CONFIG"
else
    echo "==> No base config found, using defaults"
    touch "$FINAL_CONFIG"
fi

# ── Auth Injection (Single Source of Truth) ──
# Inject password from environment variable if set, overriding any hardcoded config
if [[ -n "${REDIS_PASSWORD:-}" ]]; then
    echo "==> Injecting REDIS_PASSWORD into configuration..."
    echo "" >> "$FINAL_CONFIG"
    echo "# ── Auth injected from ENV ──" >> "$FINAL_CONFIG"
    echo "requirepass $REDIS_PASSWORD" >> "$FINAL_CONFIG"
fi

# Adjust permissions for /data (non-recursive to avoid permission errors on mountpoints)
echo "==> Adjusting permissions for /data..."
chown redis:redis /data 2>/dev/null || true
chmod 700 /data 2>/dev/null || true

# Start Redis with merged config
# We try to drop privileges to 'redis' user, but fallback to 'root' if /data is not writable
if [ "$(id -u)" = '0' ]; then
    if su-exec redis test -w /data; then
        echo "  ✅ /data is writable by 'redis' user. Dropping privileges..."
        chown redis:redis "$FINAL_CONFIG" 2>/dev/null || true
        exec su-exec redis redis-server "$FINAL_CONFIG"
    else
        echo "  ⚠️  /data is NOT writable by 'redis' user! Running as 'root' instead."
        exec redis-server "$FINAL_CONFIG"
    fi
else
    exec redis-server "$FINAL_CONFIG"
fi
