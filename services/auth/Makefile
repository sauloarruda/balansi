.PHONY: build deploy clean deps migrate-up migrate-down migrate-install dev generate-secret cognito-local-up cognito-local-down cognito-local-setup cognito-setup test test-unit test-integration test-coverage lint lint-fix install-linter help

# Default target: show help
.DEFAULT_GOAL := help

# Show help message
help:
	@echo "Available commands:"
	@echo ""
	@echo "  Development:"
	@echo "    make dev              - Run API locally (development mode)"
	@echo "    make build-local      - Build binary for local testing"
	@echo "    make deps             - Install/update Go dependencies"
	@echo ""
	@echo "  Build & Deploy:"
	@echo "    make build            - Build for Linux ARM64 (Lambda)"
	@echo "    make deploy           - Deploy to AWS Lambda (uses SERVERLESS_STAGE or 'dev')"
	@echo "    make deploy-function  - Deploy function only (faster)"
	@echo "    make clean            - Remove generated files"
	@echo ""
	@echo "  Database:"
	@echo "    make migrate-install  - Install migrate CLI tool"
	@echo "    make migrate-up       - Run database migrations"
	@echo "    make migrate-down     - Rollback last migration"
	@echo ""
	@echo "  Cognito Local:"
	@echo "    make cognito-local-up    - Start cognito-local server"
	@echo "    make cognito-local-down  - Stop cognito-local server"
	@echo "    make cognito-setup       - Setup Cognito User Pool in cognito-local"
	@echo ""
	@echo "  Testing:"
	@echo "    make test             - Run unit tests (skips integration)"
	@echo "    make test-unit        - Run unit tests only"
	@echo "    make test-integration - Run integration tests (requires Docker)"
	@echo "    make test-coverage    - Run tests with coverage report"
	@echo ""
	@echo "  Code Quality:"
	@echo "    make lint             - Run linter (golangci-lint)"
	@echo "    make lint-fix         - Run linter and auto-fix issues"
	@echo "    make install-linter   - Install golangci-lint"
	@echo ""
	@echo "  Utilities:"
	@echo "    make generate-secret  - Generate secure ENCRYPTION_SECRET"
	@echo "    make install-serverless - Install Serverless Framework CLI"
	@echo ""
	@echo "  Help:"
	@echo "    make help             - Show this help message"

# Install dependencies
deps:
	go mod tidy

# Build for Linux ARM64 (Lambda)
build:
	GOOS=linux GOARCH=arm64 CGO_ENABLED=0 go build -tags lambda.norpc -o bootstrap cmd/api/main.go

# Local build (for testing)
build-local:
	go build -o bin/api cmd/api/main.go

# Run locally (development)
dev: build-local
	@if [ -f .env ]; then \
		export $$(grep -v '^#' .env | xargs); \
	fi; \
	./bin/api

# Deploy
deploy: build
	@STAGE=$${SERVERLESS_STAGE:-dev}; \
	if [ -f .env.$$STAGE ]; then \
		echo "Loading environment variables from .env.$$STAGE"; \
		export $$(grep -v '^#' .env.$$STAGE | xargs); \
	fi; \
	if [ -z "$$DATABASE_URL" ]; then \
		echo "Error: DATABASE_URL not set. Create .env.$$STAGE file or export it."; \
		echo "Example: cp .env.dev.example .env.dev"; \
		exit 1; \
	fi; \
	serverless deploy --stage $$STAGE

# Deploy function only
deploy-function: build
	@STAGE=$${SERVERLESS_STAGE:-dev}; \
	if [ -f .env.$$STAGE ]; then \
		echo "Loading environment variables from .env.$$STAGE"; \
		export $$(grep -v '^#' .env.$$STAGE | xargs); \
	fi; \
	serverless deploy function -f api --stage $$STAGE

# Clean generated files
clean:
	rm -f bootstrap function.zip bin/api

# Install Serverless Framework (if needed)
install-serverless:
	npm install -g serverless

# Install migrate CLI tool
migrate-install:
	go install -tags 'postgres' github.com/golang-migrate/migrate/v4/cmd/migrate@latest

# Generate a secure encryption secret
generate-secret:
	@echo "Generating secure ENCRYPTION_SECRET..."
	@if command -v openssl > /dev/null; then \
		SECRET=$$(openssl rand -hex 32); \
		echo ""; \
		echo "ENCRYPTION_SECRET=$$SECRET"; \
		echo ""; \
		echo "Add this to your .env.dev file:"; \
		echo "ENCRYPTION_SECRET=$$SECRET"; \
	else \
		echo "openssl not found. Using alternative method..."; \
		SECRET=$$(head -c 32 /dev/urandom | xxd -p -c 32 | tr -d '\n'); \
		echo ""; \
		echo "ENCRYPTION_SECRET=$$SECRET"; \
		echo ""; \
		echo "Add this to your .env.dev file:"; \
		echo "ENCRYPTION_SECRET=$$SECRET"; \
	fi

# Run migrations up
migrate-up:
	@if [ -f .env ]; then \
		export $$(grep -v '^#' .env | xargs); \
	fi; \
	if [ -z "$$DATABASE_URL" ]; then \
		echo "Error: DATABASE_URL environment variable is not set"; \
		echo "Please set it in .env file or export it"; \
		exit 1; \
	fi; \
	migrate -path ./migrations -database "$$DATABASE_URL" up

# Rollback last migration
migrate-down:
	@if [ -f .env ]; then \
		export $$(grep -v '^#' .env | xargs); \
	fi; \
	if [ -z "$$DATABASE_URL" ]; then \
		echo "Error: DATABASE_URL environment variable is not set"; \
		echo "Please set it in .env file or export it"; \
		exit 1; \
	fi; \
	migrate -path ./migrations -database "$$DATABASE_URL" down 1

# Start cognito-local
cognito-local-up:
	@if ! command -v npx > /dev/null; then \
		echo "Error: npx not found. Please install Node.js."; \
		exit 1; \
	fi
	@echo "Starting cognito-local..."
	@CODE=123123 npx cognito-local > /dev/null 2>&1 &
	@echo "Waiting for cognito-local to be ready..."
	@sleep 3
	@echo "cognito-local is ready on http://localhost:9229"

# Stop cognito-local
cognito-local-down:
	@pkill -f "cognito-local" || true
	@echo "cognito-local stopped"

# Setup Cognito User Pool and Client in cognito-local
cognito-local-setup:
	@if ! curl -s http://localhost:9229 > /dev/null 2>&1; then \
		echo "Error: cognito-local is not running. Run 'make cognito-local-up' first."; \
		exit 1; \
	fi
	@bash scripts/setup-cognito.sh

# Alias for cognito-local-setup
cognito-setup: cognito-local-setup

# Run all tests (unit tests only, skips integration tests)
test:
	go test -v -short ./...

# Run unit tests only
test-unit:
	go test -v -short ./...

# Run tests with better formatting using gotestsum
# Install: go install gotest.tools/gotestsum@latest
test-pretty:
	@if command -v gotestsum > /dev/null; then \
		gotestsum --format testname -- -short ./...; \
	else \
		echo "gotestsum not found. Install with: go install gotest.tools/gotestsum@latest"; \
		echo "Falling back to standard go test..."; \
		go test -v -short ./...; \
	fi

# Run integration tests (requires Docker and cognito-local)
test-integration:
	@echo "Running integration tests..."
	@echo "Note: Integration tests require Docker for testcontainers"
	go test -v ./internal/integration/...

# Run tests with coverage report
test-coverage:
	go test -v -short -coverprofile=coverage.out ./...
	go tool cover -html=coverage.out -o coverage.html
	@echo "Coverage report generated: coverage.html"
	@echo "Coverage summary:"
	@go tool cover -func=coverage.out | tail -1

# Install golangci-lint (if not already installed)
install-linter:
	@if ! command -v golangci-lint > /dev/null; then \
		echo "Installing golangci-lint..."; \
		curl -sSfL https://raw.githubusercontent.com/golangci/golangci-lint/master/install.sh | sh -s -- -b $$(go env GOPATH)/bin latest; \
	else \
		echo "golangci-lint is already installed"; \
		golangci-lint --version; \
	fi

# Run linter
lint: install-linter
	@echo "Running golangci-lint..."
	@golangci-lint run ./...

# Run linter and auto-fix issues
lint-fix: install-linter
	@echo "Running golangci-lint with auto-fix..."
	@golangci-lint run --fix ./...
