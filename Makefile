SHELL := /bin/bash
.DEFAULT_GOAL := help

COMPOSE := docker compose --env-file versions.env
CLICKHOUSE := $(COMPOSE) exec -T clickhouse1 clickhouse-client
KAFKA_BOOTSTRAP := kafka:19092

.PHONY: help up down restart ps logs pull wait bootstrap kafka-topic schema diagnostics support-bundle incident-syntax versions

help:
	@echo "ClickHouse Customer Support Engineering Lab"
	@echo
	@echo "Available targets:"
	@echo "  make up              Start the lab services"
	@echo "  make down            Stop the lab services"
	@echo "  make restart         Restart the lab services"
	@echo "  make ps              Show service status"
	@echo "  make logs            Follow service logs"
	@echo "  make pull            Pull pinned container images"
	@echo "  make wait            Wait for ClickHouse and Kafka readiness"
	@echo "  make kafka-topic     Create/verify the saas-events Kafka topic"
	@echo "  make schema          Apply all ClickHouse schema files"
	@echo "  make bootstrap       Start, wait, create topic, and apply schema"
	@echo "  make diagnostics     Run all support diagnostic checks"
	@echo "  make support-bundle  Collect a support bundle"
	@echo "  make incident-syntax Syntax-check all incident shell scripts"
	@echo "  make versions        Display pinned component versions"

up:
	$(COMPOSE) up -d

down:
	$(COMPOSE) down

restart:
	$(COMPOSE) restart

ps:
	$(COMPOSE) ps

logs:
	$(COMPOSE) logs -f --tail=100

pull:
	$(COMPOSE) pull

wait:
	@echo "Waiting for ClickHouse..."
	@attempt=0; until $(CLICKHOUSE) --query "SELECT 1" >/dev/null 2>&1; do \
	    attempt=$$((attempt + 1)); \
	    if [ $$attempt -ge 60 ]; then \
	        echo "ERROR: ClickHouse did not become ready within 120 seconds."; \
	        exit 1; \
	    fi; \
	    sleep 2; \
	done
	@echo "PASS: ClickHouse is ready."
	@echo "Waiting for Kafka..."
	@attempt=0; until $(COMPOSE) exec -T kafka /opt/kafka/bin/kafka-topics.sh --bootstrap-server $(KAFKA_BOOTSTRAP) --list >/dev/null 2>&1; do \
	    attempt=$$((attempt + 1)); \
	    if [ $$attempt -ge 60 ]; then \
	        echo "ERROR: Kafka did not become ready within 120 seconds."; \
	        exit 1; \
	    fi; \
	    sleep 2; \
	done
	@echo "PASS: Kafka is ready."

kafka-topic:
	@echo "Creating/verifying Kafka topic..."
	$(COMPOSE) exec -T kafka bash -s < kafka/create-topics.sh

schema:
	@set -e; \
	for file in sql/schema/*.sql; do \
	    echo "Applying $$file"; \
	    $(CLICKHOUSE) --multiquery < "$$file"; \
	done
	@echo "PASS: ClickHouse schema applied."

bootstrap:
	@$(MAKE) up
	@$(MAKE) wait
	@$(MAKE) kafka-topic
	@$(MAKE) schema
	@echo "PASS: lab bootstrap complete."

diagnostics:
	@set -e; \
	for script in diagnostics/check-*.sh; do \
	    echo; \
	    echo "Running $$script"; \
	    bash "$$script"; \
	done

support-bundle:
	bash diagnostics/collect-support-bundle.sh

incident-syntax:
	@set -e; \
	for script in incidents/INC-*/inject-failure.sh incidents/INC-*/validate.sh; do \
	    echo "Checking $$script"; \
	    bash -n "$$script"; \
	done
	@echo "PASS: all incident shell scripts passed bash syntax checks."

versions:
	@cat versions.env
