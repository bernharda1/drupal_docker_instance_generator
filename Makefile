SHELL := /bin/bash
# Composer cache mounted at ./.cache/composer -> container /tmp/composer-cache
COMPOSER_CACHE_DIR := ./.cache/composer
ENV_FILE ?= .env.dev
COMPOSE := docker compose --env-file $(ENV_FILE)

ensure-composer-cache:
	@mkdir -p $(COMPOSER_CACHE_DIR)
	@chown -R $$(id -u):$$(id -g) $(COMPOSER_CACHE_DIR) || true

.PHONY: help ensure-composer-cache ensure-node-modules composer-install composer-update composer-require drush-status drush-cr drush-site-install node-ci node-build perms

help:
	@echo "Usage: make <target> [ENV_FILE=.env.dev|.env.stag|.env.prod]"
	@echo ""
	@echo "Targets:"
	@echo "  composer-install    Run composer install"
	@echo "  composer-update     Run composer update"
	@echo "  composer-require    Require a composer package"
	@echo "  drush-status        Show Drupal status"
	@echo "  drush-cr            Run drush cache rebuild"
	@echo "  drush-site-install  Run drush site:install"
	@echo "  node-ci             Run npm ci"
	@echo "  node-build          Run npm run build"
	@echo "  perms               Reset host file permissions"
	@echo ""
	@echo "Examples:"
	@echo "  make composer-install ENV_FILE=.env.dev"
	@echo "  make drush-status ENV_FILE=.env.stag"
	@echo "  make node-build ENV_FILE=.env.prod"

composer-install: ensure-composer-cache
	$(COMPOSE) run --rm composer install --no-interaction

composer-update: ensure-composer-cache
	$(COMPOSE) run --rm composer update --no-interaction

composer-require: ensure-composer-cache
	@read -p "Package (vendor/package): " pkg; \
	$(COMPOSE) run --rm composer require $$pkg

drush-status:
	$(COMPOSE) run --rm drush vendor/bin/drush status

drush-cr:
	$(COMPOSE) run --rm drush vendor/bin/drush cr

drush-site-install:
	@read -p "DB URL (mysql://user:pass@host/db): " dburl; \
	$(COMPOSE) run --rm drush vendor/bin/drush site:install standard --db-url=$$dburl --site-name="Site" -y

node-ci:
	@$(MAKE) ensure-node-modules
	$(COMPOSE) run --rm node npm ci

node-build:
	@$(MAKE) ensure-node-modules
	$(COMPOSE) run --rm node npm run build

ensure-node-modules:
	@mkdir -p drupal/web/node_modules
	@chown -R $$(id -u):$$(id -g) drupal/web/node_modules || true

perms:
	sudo chown -R dev:dev drupal
	find drupal -type d -exec chmod 2775 {} +
	find drupal -type f -exec chmod 664 {} +
