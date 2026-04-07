# ═══════════════════════════════════════════════════════════════
# Redis Cache Dockerfile — Pinned base image, non-root ready
# ═══════════════════════════════════════════════════════════════
FROM redis:7.2-alpine

LABEL maintainer="infrastructure-team"
LABEL service="redis-cache"
LABEL description="Redis cache with custom entrypoint for config merging"

# Install runtime dependencies
RUN apk add --no-cache bash curl su-exec tzdata

# Copy scripts into image
COPY scripts/healthcheck.sh /usr/local/bin/healthcheck.sh
COPY scripts/entrypoint.sh /usr/local/bin/custom-entrypoint.sh

RUN chmod +x /usr/local/bin/healthcheck.sh \
    /usr/local/bin/custom-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/custom-entrypoint.sh"]

EXPOSE 6379
