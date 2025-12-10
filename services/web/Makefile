.PHONY: build clean deploy dev install-deps help

# Default target: show help
.DEFAULT_GOAL := help

# Show help message
help:
	@echo "Available commands:"
	@echo ""
	@echo "  Development:"
	@echo "    make dev              - Start SvelteKit dev server (with hot reload)"
	@echo "    make install-deps     - Install npm dependencies"
	@echo ""
	@echo "  Build:"
	@echo "    make build            - Build SvelteKit app for production"
	@echo "    make clean            - Remove build artifacts and cache"
	@echo ""
	@echo "  Deployment:"
	@echo "    make deploy           - Deploy to AWS Amplify"
	@echo ""
	@echo "  Help:"
	@echo "    make help             - Show this help message"

# Install dependencies
install-deps:
	npm install

# Full build
build:
	@echo "Building SvelteKit app..."
	npm run build
	@echo "Build completed!"

# Development mode: start SvelteKit dev server
# Automatically loads environment variables from .env file if it exists
dev:
	@if [ -f .env ]; then \
		echo "✅ Loading environment variables from .env file"; \
		export $$(cat .env | grep -v "^#" | xargs) && npm run dev; \
	else \
		echo "⚠️  No .env file found. Using system environment variables."; \
		echo "   Create .env file from .env.example if needed."; \
		npm run dev; \
	fi

# Clean generated files
clean:
	rm -rf build/
	rm -rf .svelte-kit/
	rm -rf node_modules/.vite/

# Deploy to AWS Amplify
deploy:
	./scripts/deploy-amplify.sh
