import { defineConfig, devices } from "@playwright/test";

/**
 * Playwright configuration for E2E tests
 * @see https://playwright.dev/docs/test-configuration
 */
export default defineConfig({
	testDir: "./tests",
	fullyParallel: true,
	forbidOnly: !!process.env.CI,
	retries: process.env.CI ? 2 : 0,
	workers: process.env.CI ? 1 : undefined,
	reporter: [["html", { open: "never" }], ["list"]],
	timeout: 30000, // 30 seconds per test (allows for API calls)
	expect: {
		timeout: 10000, // 10 seconds for assertions (allows for network requests)
	},
	use: {
		baseURL: "http://localhost:8081", // Use different port for tests (8081 instead of 8080)
		trace: "on-first-retry",
		screenshot: "only-on-failure",
		// Run headless by default, but allow override with HEADLESS=false
		headless: process.env.HEADLESS !== "false",
		// Navigation timeout
		navigationTimeout: 10000,
		// Set locale to English for tests
		locale: "en-US",
	},

	projects: [
		{
			name: "chromium",
			use: { ...devices["Desktop Chrome"] },
		},
	],

	// Run local dev server before starting tests
	// Using different ports (3001 for API, 8081 for web) to avoid conflicts with dev servers
	webServer: [
		{
			command: process.env.SKIP_BUILD
				? 'cd ../../services/auth && [ -f .env ] && export $(cat .env | grep -v "^#" | xargs) && PORT=3001 ./bin/api'
				: 'cd ../../services/auth && go build -o bin/api cmd/api/main.go && [ -f .env ] && export $(cat .env | grep -v "^#" | xargs) && PORT=3001 ./bin/api',
			port: 3001, // Test API port (dev uses 3000)
			reuseExistingServer: false, // Always create new server for tests
			timeout: 30000, // 30 seconds for build and startup
			stdout: "pipe",
			stderr: "pipe",
			shell: true,
			env: {
				PORT: "3001",
				DATABASE_URL: process.env.DATABASE_URL || "postgres://test:test@localhost:5432/balansi_test?sslmode=disable",
				ENCRYPTION_SECRET: process.env.ENCRYPTION_SECRET || "test-secret-key-for-ci-testing-only-32-chars",
				AWS_REGION: process.env.AWS_REGION || "us-east-1",
				COGNITO_USER_POOL_ID: process.env.COGNITO_USER_POOL_ID || "local_test_pool",
				COGNITO_CLIENT_ID: process.env.COGNITO_CLIENT_ID || "test_client_id",
				COGNITO_ENDPOINT: process.env.COGNITO_ENDPOINT || "http://127.0.0.1:9229",
				FRONTEND_DOMAIN: process.env.FRONTEND_DOMAIN || "localhost:8081",
				API_DOMAIN: process.env.API_DOMAIN || "localhost:3001",
				COOKIE_DOMAIN: process.env.COOKIE_DOMAIN || "localhost",
			},
		},
		{
			command: process.env.SKIP_BUILD
				? "npm run preview -- --port 8081"
				: "npm run build && npm run preview -- --port 8081",
			port: 8081, // Test web port (dev uses 8080)
			reuseExistingServer: false, // Always create new server for tests
			timeout: 60000, // 60 seconds for build and startup (increased for CI)
			stdout: "pipe",
			stderr: "pipe",
			env: {
				PORT: "8081",
				VITE_API_URL: "", // Use relative path to leverage Vite proxy
				VITE_API_PROXY_TARGET: "http://localhost:3001", // Point proxy to test API
			},
		},
	],
});
