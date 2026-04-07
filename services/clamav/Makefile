# ═══════════════════════════════════════════════════════════════
# ClamAV Service — Production Environment Makefile
# ═══════════════════════════════════════════════════════════════

.PHONY: help up down restart logs status build clean

# designate environment
ENV := prod
export APP_ENV := $(ENV)

# ── Derived variables ──
COMPOSE_BASE    := compose/docker-compose.yml
COMPOSE_OVERRIDE := compose/docker-compose.prod.yml
ENV_FILE        := env/prod.env
PROJECT_NAME    := clamav-prod
CONTAINER_NAME  := clamav-prod
GATEWAY_NETWORK := gateway_prod_network
INTERNAL_NETWORK := clam_internal_prod

# ── Paths ──
export DATA_PATH_BASE := /root/Desktop/docker-infra-data/prod/clamav

# ── Network Config ──
GATEWAY_SUBNET  := 172.22.0.0/24
INTERNAL_SUBNET := 172.22.6.0/28

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

up: network-create ## Start clamav
	$(DC) up -d --build
	@echo "✅ $(CONTAINER_NAME) started"

down: ## Stop clamav
	$(DC) down
	@echo "✅ $(CONTAINER_NAME) stopped"

restart: ## Restart clamav
	$(DC) restart

logs: ## Tail logs
	$(DC) logs -f --tail=100

status: ## Show container status
	@docker inspect --format='  Container: {{.Name}} [{{.State.Status}}]' $(CONTAINER_NAME) 2>/dev/null || echo "  Container: NOT FOUND"

clean: ## Remove container + volume
	$(DC) down -v
