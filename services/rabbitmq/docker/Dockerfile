# ═══════════════════════════════════════════════════════════════
# RabbitMQ Dockerfile — Standardized, script-embedded image
# ═══════════════════════════════════════════════════════════════
FROM rabbitmq:3.13-management-alpine

LABEL maintainer="infrastructure-team"
LABEL service="rabbitmq"
LABEL description="RabbitMQ with custom entrypoint and healthcheck baked in"

# Install runtime dependencies
RUN apk add --no-cache bash curl tzdata && \
    rm -rf /var/cache/apk/*

# Enable production plugins (offline to keep image static)
RUN rabbitmq-plugins enable --offline rabbitmq_prometheus

# Create app directories with proper permissions
RUN mkdir -p /var/lib/rabbitmq/backups && \
    chown -R rabbitmq:rabbitmq /var/lib/rabbitmq/backups

# Copy scripts into image
COPY scripts/ /usr/local/bin/scripts/
RUN chmod +x /usr/local/bin/scripts/*.sh

# Standardize healthcheck location
RUN ln -s /usr/local/bin/scripts/healthcheck.sh /usr/local/bin/healthcheck.sh

# Use the standardized entrypoint
ENTRYPOINT ["/usr/local/bin/scripts/entrypoint.sh"]

# Standard ports
EXPOSE 5672 15672
