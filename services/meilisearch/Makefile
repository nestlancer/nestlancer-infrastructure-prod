# ═══════════════════════════════════════════════════════════════
# Meilisearch Service — Production Environment Makefile
# ═══════════════════════════════════════════════════════════════

.PHONY: help up down restart logs status build clean backup restore

# designate environment
ENV := prod
export APP_ENV := $(ENV)

# ── Derived variables ──
COMPOSE_BASE    := compose/docker-compose.yml
COMPOSE_OVERRIDE := compose/docker-compose.prod.yml
ENV_FILE        := env/prod.env
PROJECT_NAME    := meili-prod
CONTAINER_NAME  := meilisearch-prod
GATEWAY_NETWORK := gateway_prod_network
INTERNAL_NETWORK := meili_internal_prod

# ── Paths ──
export DATA_PATH_BASE := /root/Desktop/docker-infra-data/prod/meilisearch

# ── Network Config ──
GATEWAY_SUBNET  := 172.22.0.0/24
INTERNAL_SUBNET := 172.22.5.0/28

# Common docker compose command
DC := docker compose -f $(COMPOSE_BASE) -f $(COMPOSE_OVERRIDE) --env-file $(ENV_FILE) -p $(PROJECT_NAME)

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

network-create: ## Create networks for PROD (idempotent)
	@if ! docker network inspect $(GATEWAY_NETWORK) >/dev/null 2>&1; then \
		docker network create --driver bridge --subnet=$(GATEWAY_SUBNET) $(GATEWAY_NETWORK); \
	fi
	@if ! docker network inspect $(INTERNAL_NETWORK) >/dev/null 2>&1; then \
		docker network create --driver bridge --internal --subnet=$(INTERNAL_SUBNET) $(INTERNAL_NETWORK); \
	fi

up: network-create ## Start meilisearch
	$(DC) up -d --build
	@echo "✅ $(CONTAINER_NAME) started"

down: ## Stop meilisearch
	$(DC) down
	@echo "✅ $(CONTAINER_NAME) stopped"

restart: ## Restart meilisearch
	$(DC) restart

logs: ## Tail logs
	$(DC) logs -f --tail=100

status: ## Show container status
	@docker inspect --format='  Container: {{.Name}} [{{.State.Status}}]' $(CONTAINER_NAME) 2>/dev/null || echo "  Container: NOT FOUND"

backup: ## Trigger Meilisearch dump (API) inside container
	docker exec $(CONTAINER_NAME) /usr/local/bin/scripts/backup.sh
	@echo "✅ Backup complete for $(CONTAINER_NAME)"

restore: ## Validate a dump path inside the container (FILE=path or basename under /meili_data/dumps)
	@if [ -z "$(FILE)" ]; then echo "❌ Usage: make restore FILE=<dump_basename_or_container_path>"; exit 1; fi
	docker exec $(CONTAINER_NAME) /usr/local/bin/scripts/restore.sh "$(FILE)"

clean: ## Remove container + volume
	$(DC) down -v
