# ═══════════════════════════════════════════════════════════════
# ClamAV Dockerfile — Standardized with healthcheck
# ═══════════════════════════════════════════════════════════════
FROM clamav/clamav:latest

LABEL maintainer="infrastructure-team"
LABEL service="clamav"
LABEL description="ClamAV with custom healthcheck baked in"

# Install runtime dependencies
RUN apk add --no-cache tzdata

# Copy scripts into image
COPY scripts/ /usr/local/bin/scripts/
RUN chmod +x /usr/local/bin/scripts/*.sh

# Standardize healthcheck location
RUN ln -s /usr/local/bin/scripts/healthcheck.sh /usr/local/bin/healthcheck.sh

# Use the official entrypoint as it manages multiple processes
# But we could wrap it if needed. For now, we'll keep it simple.

# Standard ports
EXPOSE 3310
