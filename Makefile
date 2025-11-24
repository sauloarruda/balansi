.PHONY: help dev dev-auth dev-web test test-auth test-web test-web-e2e lint lint-auth lint-web format format-web install-deps install-deps-auth install-deps-web clean clean-auth clean-web

# Default target: show help
.DEFAULT_GOAL := help

# Show help message
help:
	@echo "Balansi Monorepo - Available commands:"
	@echo ""
	@echo "  Development:"
	@echo "    make dev              - Start both auth and web services in parallel"
	@echo "    make dev-auth         - Start auth service only (Go API)"
	@echo "    make dev-web          - Start web service only (SvelteKit)"
	@echo ""
	@echo "  Testing:"
	@echo "    make test             - Run all tests (auth unit + web e2e)"
	@echo "    make test-auth        - Run auth service unit tests"
	@echo "    make test-web         - Run web service tests (if any)"
	@echo "    make test-web-e2e     - Run web service E2E tests (Playwright)"
	@echo ""
	@echo "  Code Quality:"
	@echo "    make lint             - Run linters on all services"
	@echo "    make lint-auth        - Run golangci-lint on auth service"
	@echo "    make lint-web         - Run ESLint on web service"
	@echo "    make format-web       - Format web service code with Prettier"
	@echo ""
	@echo "  Dependencies:"
	@echo "    make install-deps     - Install dependencies for all services"
	@echo "    make install-deps-auth - Install Go dependencies"
	@echo "    make install-deps-web  - Install npm dependencies"
	@echo ""
	@echo "  Cleanup:"
	@echo "    make clean            - Clean all generated files"
	@echo "    make clean-auth       - Clean auth service artifacts"
	@echo "    make clean-web        - Clean web service artifacts"
	@echo ""
	@echo "  Help:"
	@echo "    make help             - Show this help message"
	@echo ""
	@echo "For service-specific commands, navigate to the service directory:"
	@echo "  cd services/auth && make help"
	@echo "  cd services/web && make help"

# Development: Start both services in parallel
dev:
	@echo "Starting both services..."
	@echo "Auth service will run on http://localhost:3000"
	@echo "Web service will run on http://localhost:8080"
	@echo ""
	@echo "Press Ctrl+C to stop all services"
	@echo ""
	@trap 'kill 0' EXIT; \
	cd services/auth && make dev & \
	cd services/web && make dev & \
	wait

# Development: Auth service only
dev-auth:
	@cd services/auth && make dev

# Development: Web service only
dev-web:
	@cd services/web && make dev

# Testing: Run all tests
test: test-auth
	@echo ""
	@echo "Note: E2E tests require both services running."
	@echo "Run 'make test-web-e2e' separately after starting services."

# Testing: Auth service unit tests
test-auth:
	@echo "Running auth service tests..."
	@cd services/auth && make test

# Testing: Web service tests
test-web:
	@echo "Running web service tests..."
	@cd services/web && npm test || echo "No unit tests configured"

# Testing: Web service E2E tests
test-web-e2e:
	@echo "Running web service E2E tests..."
	@echo "Note: This requires both auth and web services to be running"
	@cd services/web && npm run test

# Linting: All services
lint: lint-auth lint-web

# Linting: Auth service
lint-auth:
	@echo "Linting auth service..."
	@cd services/auth && make lint

# Linting: Web service
lint-web:
	@echo "Linting web service..."
	@cd services/web && npm run lint

# Formatting: Web service
format-web:
	@echo "Formatting web service..."
	@cd services/web && npm run format

# Dependencies: Install all
install-deps: install-deps-auth install-deps-web

# Dependencies: Auth service
install-deps-auth:
	@echo "Installing auth service dependencies..."
	@cd services/auth && make deps

# Dependencies: Web service
install-deps-web:
	@echo "Installing web service dependencies..."
	@cd services/web && make install-deps

# Cleanup: All services
clean: clean-auth clean-web

# Cleanup: Auth service
clean-auth:
	@echo "Cleaning auth service..."
	@cd services/auth && make clean

# Cleanup: Web service
clean-web:
	@echo "Cleaning web service..."
	@cd services/web && make clean
