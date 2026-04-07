# ═══════════════════════════════════════════════════════════════
# Redis Pub/Sub Dockerfile — Pinned base image
# ═══════════════════════════════════════════════════════════════
FROM redis:7.2-alpine

LABEL maintainer="infrastructure-team"
LABEL service="redis-pubsub"
LABEL description="Redis pub/sub with custom entrypoint for config merging"

RUN apk add --no-cache bash curl su-exec tzdata

COPY scripts/healthcheck.sh /usr/local/bin/healthcheck.sh
COPY scripts/entrypoint.sh /usr/local/bin/custom-entrypoint.sh

RUN chmod +x /usr/local/bin/healthcheck.sh \
    /usr/local/bin/custom-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/custom-entrypoint.sh"]

EXPOSE 6379
