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
				: 'cd ../../services/auth && (make build-local || echo "Build failed, using existing binary") && [ -f .env ] && export $(cat .env | grep -v "^#" | xargs) && PORT=3001 ./bin/api',
			port: 3001, // Test API port (dev uses 3000)
			reuseExistingServer: false, // Always create new server for tests
			timeout: 30000, // 30 seconds for build and startup
			stdout: "pipe",
			stderr: "pipe",
			shell: true,
			env: {
				PORT: "3001",
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
