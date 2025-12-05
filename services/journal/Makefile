.PHONY: setup deps dev build test test-coverage lint lint-fix migrate-up migrate-down deploy deploy-function clean generate-secret help

# Default target: show help
.DEFAULT_GOAL := help

# Show help message
help:
	@echo "Available commands:"
	@echo ""
	@echo "  Development:"
	@echo "    make setup            - Install dependencies and setup database"
	@echo "    make deps             - Install/update dependencies"
	@echo "    make dev              - Run API locally (development mode)"
	@echo ""
	@echo "  Build & Deploy:"
	@echo "    make build            - Build release for Lambda"
	@echo "    make deploy           - Deploy to AWS Lambda (uses SERVERLESS_STAGE or 'dev')"
	@echo "    make deploy-function  - Deploy function only (faster)"
	@echo "    make clean            - Remove generated files"
	@echo ""
	@echo "  Database:"
	@echo "    make migrate-up       - Run database migrations"
	@echo "    make migrate-down     - Rollback last migration"
	@echo "    make migrate-reset    - Reset database (drop, create, migrate)"
	@echo ""
	@echo "  Testing:"
	@echo "    make test             - Run all tests"
	@echo "    make test-coverage    - Run tests with coverage report"
	@echo ""
	@echo "  Code Quality:"
	@echo "    make lint             - Run credo linter"
	@echo "    make lint-fix         - Run credo with suggestions"
	@echo "    make format           - Format code"
	@echo "    make precommit        - Run all checks before commit"
	@echo ""
	@echo "  Utilities:"
	@echo "    make generate-secret  - Generate SECRET_KEY_BASE"
	@echo "    make iex              - Start interactive Elixir shell"
	@echo "    make routes           - List all routes"
	@echo ""
	@echo "  Help:"
	@echo "    make help             - Show this help message"

# Install dependencies
deps:
	mix deps.get

# Setup project (install deps + create database + run migrations)
setup: deps
	mix ecto.setup

# Run locally (development)
dev:
	@if [ -f .env ]; then \
		export $$(grep -v '^#' .env | xargs); \
	fi; \
	mix phx.server

# Interactive Elixir shell with Phoenix
iex:
	@if [ -f .env ]; then \
		export $$(grep -v '^#' .env | xargs); \
	fi; \
	iex -S mix phx.server

# List all routes
routes:
	mix phx.routes

# Build release for Lambda (Linux ARM64)
build:
	@echo "Building release for Lambda..."
	MIX_ENV=prod mix deps.get --only prod
	MIX_ENV=prod mix compile
	MIX_ENV=prod mix release --overwrite
	@echo "Release built successfully!"

# Deploy to AWS Lambda
deploy: build
	@STAGE=$${SERVERLESS_STAGE:-dev}; \
	if [ -f .env.$$STAGE ]; then \
		echo "Loading environment variables from .env.$$STAGE"; \
		export $$(grep -v '^#' .env.$$STAGE | xargs); \
	fi; \
	if [ -z "$$DATABASE_URL" ]; then \
		echo "Error: DATABASE_URL not set. Create .env.$$STAGE file or export it."; \
		exit 1; \
	fi; \
	serverless deploy --stage $$STAGE

# Deploy function only (faster)
deploy-function: build
	@STAGE=$${SERVERLESS_STAGE:-dev}; \
	if [ -f .env.$$STAGE ]; then \
		echo "Loading environment variables from .env.$$STAGE"; \
		export $$(grep -v '^#' .env.$$STAGE | xargs); \
	fi; \
	serverless deploy function -f api --stage $$STAGE

# Clean generated files
clean:
	rm -rf _build deps
	rm -rf priv/static

# Run migrations up
migrate-up:
	@if [ -f .env ]; then \
		export $$(grep -v '^#' .env | xargs); \
	fi; \
	mix ecto.migrate

# Rollback last migration
migrate-down:
	@if [ -f .env ]; then \
		export $$(grep -v '^#' .env | xargs); \
	fi; \
	mix ecto.rollback

# Reset database
migrate-reset:
	@if [ -f .env ]; then \
		export $$(grep -v '^#' .env | xargs); \
	fi; \
	mix ecto.reset

# Run all tests
test:
	mix test

# Run tests with coverage
test-coverage:
	mix test --cover
	@echo "Coverage report generated in cover/ directory"

# Run credo linter
lint:
	mix credo

# Run credo with suggestions
lint-fix:
	mix credo suggest

# Format code
format:
	mix format

# Run all checks before commit
precommit:
	mix precommit

# Generate a secure SECRET_KEY_BASE
generate-secret:
	@echo "Generating SECRET_KEY_BASE..."
	@mix phx.gen.secret
	@echo ""
	@echo "Add this to your .env file as SECRET_KEY_BASE"

# Install Serverless Framework (if needed)
install-serverless:
	npm install -g serverless
