# ═══════════════════════════════════════════════════════════════
# INFRASTRUCTURE — Production Environment Makefile
# Orchestrates production services
# ═══════════════════════════════════════════════════════════════

.PHONY: help \
    networks-create networks-destroy networks-list \
    env-up env-down env-restart env-status env-logs \
    postgres-up postgres-down postgres-restart postgres-logs postgres-shell postgres-status postgres-backup postgres-restore \
    redis-cache-up redis-cache-down redis-cache-restart redis-cache-logs redis-cache-shell redis-cache-status \
    redis-pubsub-up redis-pubsub-down redis-pubsub-restart redis-pubsub-logs redis-pubsub-shell redis-pubsub-status \
    rabbitmq-up rabbitmq-down rabbitmq-restart rabbitmq-logs rabbitmq-shell rabbitmq-status rabbitmq-backup rabbitmq-restore \
    meilisearch-up meilisearch-down meilisearch-restart meilisearch-logs meilisearch-status \
    clamav-up clamav-down clamav-restart clamav-logs clamav-status \
    isolation-test \
    clean prune

# designate environment
ENV := prod
SERVICES_DIR := services
NETWORKS_DIR := networks
ORCHESTRATOR_DIR := orchestrator

# ══════════════════════════════════════════════
# Help
# ══════════════════════════════════════════════
help: ## Show available targets
	@echo "╔═══════════════════════════════════════════════════════════════╗"
	@echo "║   INFRASTRUCTURE — Production Environment Makefile            ║"
	@echo "╚═══════════════════════════════════════════════════════════════╝"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-28s\033[0m %s\n", $$1, $$2}'

# ══════════════════════════════════════════════
# Network Management
# ══════════════════════════════════════════════
networks-create: ## Create networks for PROD
	@$(NETWORKS_DIR)/create-networks.sh

networks-destroy: ## Destroy networks for PROD
	@$(NETWORKS_DIR)/destroy-networks.sh

networks-list: ## List all project networks
	@$(NETWORKS_DIR)/list-networks.sh

# ══════════════════════════════════════════════
# Environment Operations
# ══════════════════════════════════════════════
env-up: ## Start all production services
	@$(ORCHESTRATOR_DIR)/start-all.sh

env-down: ## Stop all production services
	@$(ORCHESTRATOR_DIR)/stop-all.sh

env-restart: ## Restart all production services
	@$(ORCHESTRATOR_DIR)/stop-all.sh
	@$(ORCHESTRATOR_DIR)/start-all.sh

env-status: ## Show status for all production services
	@$(ORCHESTRATOR_DIR)/status.sh

env-logs: ## Show logs for all production services
	@$(ORCHESTRATOR_DIR)/logs.sh all

# ══════════════════════════════════════════════
# PostgreSQL
# ══════════════════════════════════════════════
postgres-up: ## Start postgres
	@$(MAKE) -C $(SERVICES_DIR)/postgres up

postgres-down: ## Stop postgres
	@$(MAKE) -C $(SERVICES_DIR)/postgres down

postgres-restart: ## Restart postgres
	@$(MAKE) -C $(SERVICES_DIR)/postgres restart

postgres-logs: ## Tail postgres logs
	@$(MAKE) -C $(SERVICES_DIR)/postgres logs

postgres-shell: ## Open psql shell
	@$(MAKE) -C $(SERVICES_DIR)/postgres shell

postgres-status: ## Show postgres status
	@$(MAKE) -C $(SERVICES_DIR)/postgres status

postgres-backup: ## Backup postgres
	@$(MAKE) -C $(SERVICES_DIR)/postgres backup

postgres-restore: ## Restore postgres (FILE= required)
	@$(MAKE) -C $(SERVICES_DIR)/postgres restore FILE=$(FILE)

# ══════════════════════════════════════════════
# Redis Cache
# ══════════════════════════════════════════════
redis-cache-up: ## Start redis-cache
	@$(MAKE) -C $(SERVICES_DIR)/redis-cache up

redis-cache-down: ## Stop redis-cache
	@$(MAKE) -C $(SERVICES_DIR)/redis-cache down

redis-cache-restart: ## Restart redis-cache
	@$(MAKE) -C $(SERVICES_DIR)/redis-cache restart

redis-cache-logs: ## Tail redis-cache logs
	@$(MAKE) -C $(SERVICES_DIR)/redis-cache logs

redis-cache-shell: ## Open redis-cli
	@$(MAKE) -C $(SERVICES_DIR)/redis-cache shell

redis-cache-status: ## Show redis-cache status
	@$(MAKE) -C $(SERVICES_DIR)/redis-cache status

# ══════════════════════════════════════════════
# Redis Pub/Sub
# ══════════════════════════════════════════════
redis-pubsub-up: ## Start redis-pubsub
	@$(MAKE) -C $(SERVICES_DIR)/redis-pubsub up

redis-pubsub-down: ## Stop redis-pubsub
	@$(MAKE) -C $(SERVICES_DIR)/redis-pubsub down

redis-pubsub-restart: ## Restart redis-pubsub
	@$(MAKE) -C $(SERVICES_DIR)/redis-pubsub restart

redis-pubsub-logs: ## Tail redis-pubsub logs
	@$(MAKE) -C $(SERVICES_DIR)/redis-pubsub logs

redis-pubsub-shell: ## Open redis-cli
	@$(MAKE) -C $(SERVICES_DIR)/redis-pubsub shell

redis-pubsub-status: ## Show redis-pubsub status
	@$(MAKE) -C $(SERVICES_DIR)/redis-pubsub status

# ══════════════════════════════════════════════
# RabbitMQ
# ══════════════════════════════════════════════
rabbitmq-up: ## Start rabbitmq
	@$(MAKE) -C $(SERVICES_DIR)/rabbitmq up

rabbitmq-down: ## Stop rabbitmq
	@$(MAKE) -C $(SERVICES_DIR)/rabbitmq down

rabbitmq-restart: ## Restart rabbitmq
	@$(MAKE) -C $(SERVICES_DIR)/rabbitmq restart

rabbitmq-logs: ## Tail rabbitmq logs
	@$(MAKE) -C $(SERVICES_DIR)/rabbitmq logs

rabbitmq-shell: ## Open rabbitmq shell
	@$(MAKE) -C $(SERVICES_DIR)/rabbitmq shell

rabbitmq-status: ## Show rabbitmq status
	@$(MAKE) -C $(SERVICES_DIR)/rabbitmq status

rabbitmq-backup: ## Backup rabbitmq
	@$(MAKE) -C $(SERVICES_DIR)/rabbitmq backup

rabbitmq-restore: ## Restore rabbitmq (FILE= required)
	@$(MAKE) -C $(SERVICES_DIR)/rabbitmq restore FILE=$(FILE)

# ══════════════════════════════════════════════
# Meilisearch
# ══════════════════════════════════════════════
meilisearch-up: ## Start meilisearch
	@$(MAKE) -C $(SERVICES_DIR)/meilisearch up

meilisearch-down: ## Stop meilisearch
	@$(MAKE) -C $(SERVICES_DIR)/meilisearch down

meilisearch-restart: ## Restart meilisearch
	@$(MAKE) -C $(SERVICES_DIR)/meilisearch restart

meilisearch-logs: ## Tail meilisearch logs
	@$(MAKE) -C $(SERVICES_DIR)/meilisearch logs

meilisearch-status: ## Show meilisearch status
	@$(MAKE) -C $(SERVICES_DIR)/meilisearch status

# ══════════════════════════════════════════════
# ClamAV
# ══════════════════════════════════════════════
clamav-up: ## Start clamav
	@$(MAKE) -C $(SERVICES_DIR)/clamav up

clamav-down: ## Stop clamav
	@$(MAKE) -C $(SERVICES_DIR)/clamav down

clamav-restart: ## Restart clamav
	@$(MAKE) -C $(SERVICES_DIR)/clamav restart

clamav-logs: ## Tail clamav logs
	@$(MAKE) -C $(SERVICES_DIR)/clamav logs

clamav-status: ## Show clamav status
	@$(MAKE) -C $(SERVICES_DIR)/clamav status

# ══════════════════════════════════════════════
# Validation
# ══════════════════════════════════════════════
isolation-test: ## Run isolation check (within prod env)
	@$(ORCHESTRATOR_DIR)/failover-check.sh

# ══════════════════════════════════════════════
# Cleanup
# ══════════════════════════════════════════════
clean: ## Remove containers + volumes for PROD
	@$(MAKE) -C $(SERVICES_DIR)/postgres clean
	@$(MAKE) -C $(SERVICES_DIR)/redis-cache clean
	@$(MAKE) -C $(SERVICES_DIR)/redis-pubsub clean
	@$(MAKE) -C $(SERVICES_DIR)/rabbitmq clean
	@$(MAKE) -C $(SERVICES_DIR)/meilisearch clean
	@$(MAKE) -C $(SERVICES_DIR)/clamav clean

prune: ## Docker system prune
	docker system prune -f
	docker volume prune -f
