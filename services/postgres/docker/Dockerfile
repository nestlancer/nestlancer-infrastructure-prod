# ═══════════════════════════════════════════════════════════════════
# PostgreSQL Dockerfile — Multi-stage, pinned base image
# Runs as non-root user in production
# ═══════════════════════════════════════════════════════════════════
FROM postgres:16.4-alpine

LABEL maintainer="infrastructure-team"
LABEL service="postgres"
LABEL description="PostgreSQL with custom entrypoint for config merging"

# Install runtime dependencies
RUN apk add --no-cache \
    bash \
    curl \
    openssl \
    gettext \
    tzdata \
    && rm -rf /var/cache/apk/*

# Create app directories with proper permissions
RUN mkdir -p /var/lib/postgresql/backups \
    && chown -R postgres:postgres /var/lib/postgresql/backups

# Copy all scripts
COPY scripts/ /usr/local/bin/scripts/
RUN chmod +x /usr/local/bin/scripts/*.sh

# Initial SQL scripts
COPY scripts/init-extensions.sql /docker-entrypoint-initdb.d/

# Symlink entrypoint and healthcheck for backwards compatibility/standard locations
RUN ln -s /usr/local/bin/scripts/healthcheck.sh /usr/local/bin/healthcheck.sh \
    && ln -s /usr/local/bin/scripts/entrypoint.sh /usr/local/bin/custom-entrypoint.sh

# The entrypoint handles config merging before handing off to postgres
ENTRYPOINT ["/usr/local/bin/custom-entrypoint.sh"]
CMD ["postgres"]

EXPOSE 5432
