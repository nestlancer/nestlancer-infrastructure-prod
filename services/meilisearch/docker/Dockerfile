# ═══════════════════════════════════════════════════════════════
# Meilisearch Dockerfile — Standardized with healthcheck
# ═══════════════════════════════════════════════════════════════
FROM getmeili/meilisearch:v1.12

LABEL maintainer="infrastructure-team"
LABEL service="meilisearch"
LABEL description="Meilisearch with custom healthcheck baked in"

# Install runtime dependencies (standard for this project)
RUN apk add --no-cache bash curl tzdata && \
    rm -rf /var/cache/apk/*

# Copy scripts into image
COPY scripts/ /usr/local/bin/scripts/
RUN chmod +x /usr/local/bin/scripts/*.sh

# Standardize healthcheck location
RUN ln -s /usr/local/bin/scripts/healthcheck.sh /usr/local/bin/healthcheck.sh

# Use the standardized entrypoint
ENTRYPOINT ["/usr/local/bin/scripts/entrypoint.sh"]

# Standard ports
EXPOSE 7700
