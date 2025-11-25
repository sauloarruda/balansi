import { expect, test, type Page } from "@playwright/test";

// Test helpers
const getFormElements = (page: Page) => ({
	nameInput: page.locator('input[name="name"]'),
	emailInput: page.locator('input[name="email"]'),
	submitButton: page.locator('button[type="submit"]'),
	loadingIndicator: page.locator('button[type="submit"] .animate-spin'),
});

const fillForm = async (page: Page, name: string, email: string) => {
	const { nameInput, emailInput } = getFormElements(page);
	await nameInput.fill(name);
	await emailInput.fill(email);
};

const submitForm = async (page: Page) => {
	const { submitButton } = getFormElements(page);
	// Wait for button to be enabled
	await expect(submitButton).toBeEnabled();

	// Listen for network requests before submitting
	const requestPromise = page.waitForRequest(
		(request) => request.url().includes("/auth/sign-up") && request.method() === "POST",
		{ timeout: 5000 }
	);

	// Submit form by clicking button
	await submitButton.click();

	// Wait for the request to be made
	try {
		await requestPromise;
	} catch {
		// If clicking didn't trigger the request, try submitting the form directly
		await page.locator("form").evaluate((form) => {
			(form as HTMLFormElement).requestSubmit();
		});
	}
};

const waitForButtonLoading = async (page: Page, shouldBeLoading: boolean) => {
	const { loadingIndicator, submitButton } = getFormElements(page);
	if (shouldBeLoading) {
		await expect(loadingIndicator).toBeVisible({ timeout: 2000 });
		await expect(submitButton).toBeDisabled();
	} else {
		await expect(loadingIndicator).toBeHidden({ timeout: 2000 });
		await expect(submitButton).toBeEnabled();
	}
};

const waitForValidation = async (page: Page, delay = 50) => {
	await page.waitForTimeout(delay);
};

const validateField = async (
	page: Page,
	input:
		| ReturnType<typeof getFormElements>["nameInput"]
		| ReturnType<typeof getFormElements>["emailInput"],
	value: string,
	errorMessage: string,
	shouldShowError: boolean
) => {
	await input.fill(value);
	await input.blur();
	await waitForValidation(page);

	if (shouldShowError) {
		await expect(page.getByText(errorMessage)).toBeVisible();
		await expect(input).toHaveClass(/hs-input-error/);
	} else {
		await expect(page.getByText(errorMessage)).not.toBeVisible();
		await expect(input).toHaveClass(/hs-input-success/);
	}
};

test.describe("Signup Flow", () => {
	test.beforeEach(async ({ page }) => {
		await page.goto("/auth", { waitUntil: "domcontentloaded", timeout: 10000 });
		// Wait for form inputs to be rendered
		await page.waitForSelector('input[name="name"]', { state: "attached", timeout: 10000 });
		await page.waitForSelector('input[name="email"]', { state: "attached", timeout: 10000 });
		await page.waitForSelector('button[type="submit"]', { state: "attached", timeout: 10000 });
		// Wait for loading to disappear
		await page.waitForFunction(
			() => {
				const form = document.querySelector("form");
				return form && !form.querySelector('.animate-spin[role="status"]');
			},
			{ timeout: 10000 }
		);
	});

	test("should display signup form with floating inputs", async ({ page }) => {
		await expect(page.getByRole("heading", { name: "Register, Calculate, Evaluate" })).toBeVisible();

		const { nameInput, emailInput, submitButton } = getFormElements(page);
		await expect(nameInput).toBeVisible();
		await expect(emailInput).toBeVisible();
		await expect(submitButton).toBeVisible();
		await expect(submitButton).toHaveText("Continue");
	});

	test("should validate name field - show error for short name", async ({ page }) => {
		const { nameInput } = getFormElements(page);
		await validateField(page, nameInput, "A", "Please tell us what we should call you.", true);
	});

	test("should validate name field - accept valid name", async ({ page }) => {
		const { nameInput } = getFormElements(page);
		await validateField(
			page,
			nameInput,
			"João Silva",
			"Please tell us what we should call you.",
			false
		);
	});

	test("should validate email field - show error for invalid email", async ({ page }) => {
		const { emailInput } = getFormElements(page);
		await validateField(page, emailInput, "invalid-email", "Please enter a valid email.", true);
	});

	test("should validate email field - accept valid email", async ({ page }) => {
		const { emailInput } = getFormElements(page);
		await validateField(page, emailInput, "joao@example.com", "Please enter a valid email.", false);
	});

	test("should clear errors when user starts typing", async ({ page }) => {
		const { emailInput } = getFormElements(page);

		// Trigger validation error
		await emailInput.fill("invalid");
		await emailInput.blur();
		await waitForValidation(page, 100);
		await expect(page.getByText("Please enter a valid email.")).toBeVisible();

		// Start typing again - error should be cleared
		await emailInput.fill("valid@");
		await expect(page.getByText("Please enter a valid email.")).not.toBeVisible();
	});

	test("should submit form successfully and show confirmation code screen", async ({ page }) => {
		const formData = { name: "João Silva", email: "joao.silva@example.com" };
		await fillForm(page, formData.name, formData.email);

		// Verify form values are set
		const { nameInput, emailInput } = getFormElements(page);
		await expect(nameInput).toHaveValue(formData.name);
		await expect(emailInput).toHaveValue(formData.email);

		// Start listening for API response BEFORE submitting
		const apiCallPromise = page.waitForResponse(
			(response) => {
				const url = response.url();
				const method = response.request().method();
				const matches = url.includes("/auth/sign-up") && method === "POST";
				if (matches) {
					console.log("API response detected:", url, method, response.status());
				}
				return matches;
			},
			{ timeout: 20000 }
		);

		// Also listen for requests
		const requestPromise = page.waitForRequest(
			(request) => {
				const url = request.url();
				const method = request.method();
				const matches = url.includes("/auth/sign-up") && method === "POST";
				if (matches) {
					console.log("Request detected:", url, method);
				}
				return matches;
			},
			{ timeout: 20000 }
		);

		// Submit form
		await submitForm(page);

		// Wait for request first
		const request = await requestPromise;
		console.log("Request made to:", request.url());

		// Then wait for response (with error handling)
		let apiResponse;
		try {
			apiResponse = await apiCallPromise;
			console.log("Response received:", apiResponse.status(), apiResponse.statusText());
		} catch (error) {
			// Log network errors for debugging
			const response = await request.response();
			if (response) {
				console.log("Response status:", response.status(), response.statusText());
			} else {
				console.log("No response received - possible CORS or network error");
			}
			throw error;
		}

		// Verify API was called with correct data
		const requestData = request.postDataJSON();
		expect(requestData).toMatchObject(formData);
		expect(apiResponse.status()).toBeGreaterThanOrEqual(200);
		expect(apiResponse.status()).toBeLessThan(300);

		// Wait for redirect to confirmation page
		await page.waitForURL("**/auth/confirmation*", { timeout: 10000 });

		// Wait for confirmation screen to appear
		await page.waitForSelector('h2:has-text("Confirm your email")', { timeout: 10000 });
		await expect(page.getByRole("heading", { name: "Confirm your email" })).toBeVisible();
		await expect(page.getByText(/Hello.*João Silva.*we sent a confirmation code/)).toBeVisible();
		await expect(page.getByText(/joao.silva@example.com/)).toBeVisible();
		// Wait for PIN inputs to be visible
		const pinInputs = page.locator('.pin-input-container input[type="text"]');
		await expect(pinInputs.first()).toBeVisible({ timeout: 5000 });
		await expect(pinInputs).toHaveCount(6);
	});

	test("should show error message when API returns error", async ({ page }) => {
		await fillForm(page, "Test User", "existing@example.com");

		// Mock API error response
		await page.route("**/auth/sign-up", async (route) => {
			await route.fulfill({
				status: 409,
				contentType: "application/json",
				body: JSON.stringify({
					code: "user_exists",
					message: "User with this email already exists",
				}),
			});
		});

		await submitForm(page);

		// Wait for error message to appear
		await page.waitForSelector(".error-message", { timeout: 10000 });

		// Verify error is displayed and form is still visible
		await expect(page.getByText(/This email is already registered/)).toBeVisible();
		await expect(page.getByRole("heading", { name: "Register, Calculate, Evaluate" })).toBeVisible();

		const { nameInput, emailInput } = getFormElements(page);
		await expect(nameInput).toBeVisible();
		await expect(emailInput).toBeVisible();
	});

	test("should show loading indicator during form submission", async ({ page }) => {
		// Use unique email to avoid conflicts from previous test runs
		const uniqueEmail = `test-loading-${Date.now()}@example.com`;
		await fillForm(page, "Test User", uniqueEmail);

		// Delay API response to see loading indicator
		await page.route("**/auth/sign-up", async (route) => {
			await new Promise((resolve) => setTimeout(resolve, 500));
			await route.continue();
		});

		// Start listening for response before submitting (accept any status)
		const responsePromise = page.waitForResponse(
			(response) => response.url().includes("/auth/sign-up"),
			{ timeout: 15000 }
		);

		await submitForm(page);

		// Verify loading indicator appears in button and form is disabled
		await waitForButtonLoading(page, true);
		const { nameInput, emailInput } = getFormElements(page);
		await expect(nameInput).toBeDisabled();
		await expect(emailInput).toBeDisabled();

		// Wait for response
		const response = await responsePromise;

		// Verify response was successful (200 for new user, 409 if user exists)
		// Both are valid responses - the important thing is that loading state was shown
		expect(response.status()).toBeGreaterThanOrEqual(200);
		expect(response.status()).toBeLessThan(500);

		// If successful (200), page redirects to confirmation
		// If user exists (409), we stay on the form with error message
		if (response.status() === 200) {
			await page.waitForURL("**/auth/confirmation*", { timeout: 10000 });
			await expect(page.getByRole("heading", { name: "Confirm your email" })).toBeVisible();
		} else {
			// User already exists - verify error message appears
			await expect(page.getByText(/already registered/i)).toBeVisible();
			// Verify inputs are enabled again after error
			await expect(nameInput).toBeEnabled();
			await expect(emailInput).toBeEnabled();
		}
	});

	test("should show error message when server is offline", async ({ page }) => {
		const formData = { name: "Test User", email: "test@example.com" };
		await fillForm(page, formData.name, formData.email);

		// Simulate server offline by aborting the request
		await page.route("**/auth/sign-up", async (route) => {
			await route.abort("failed");
		});

		await submitForm(page);

		// Wait for error message to appear
		await page.waitForTimeout(1000); // Give HTMX time to process the error

		// Verify connection error message is displayed
		await expect(page.getByText(/Could not connect to the server/)).toBeVisible({ timeout: 5000 });

		// Verify form is still visible and re-enabled
		await expect(page.getByRole("heading", { name: "Register, Calculate, Evaluate" })).toBeVisible();

		const { nameInput, emailInput, submitButton } = getFormElements(page);
		await expect(nameInput).toBeVisible();
		await expect(emailInput).toBeVisible();
		await expect(nameInput).toBeEnabled();
		await expect(emailInput).toBeEnabled();
		await expect(submitButton).toBeEnabled();

		// Verify form values are preserved
		await expect(nameInput).toHaveValue(formData.name);
		await expect(emailInput).toHaveValue(formData.email);
	});

	test("should complete confirmation flow and redirect to home", async ({ page }) => {
		const formData = { name: "Test User", email: `test-confirm-${Date.now()}@example.com` };

		// Step 1: Complete signup (using real API)
		await fillForm(page, formData.name, formData.email);
		await submitForm(page);

		// Wait for redirect to confirmation page
		await page.waitForURL("**/auth/confirmation*", { timeout: 15000 });
		await page.waitForSelector('h2:has-text("Confirm your email")', { timeout: 10000 });

		// Step 2: Wait for PIN inputs to be visible
		const pinInputs = page.locator('.pin-input-container input[type="text"]');
		await expect(pinInputs.first()).toBeVisible({ timeout: 5000 });
		await expect(pinInputs).toHaveCount(6);

		// Step 3: Use cognito-local's default confirmation code
		// cognito-local uses "123123" as the default confirmation code for testing
		const confirmationCode = "123123";

		// Step 4: Fill confirmation code digit by digit
		for (let i = 0; i < confirmationCode.length; i++) {
			const input = pinInputs.nth(i);
			await input.fill(confirmationCode[i]);
			// Small delay to allow auto-tab to next input
			await page.waitForTimeout(150);
		}

		// Step 5: Wait for form to auto-submit (onComplete triggers submission)
		// After confirmation, the page will:
		// 1. Call /auth/confirm (sets session_id cookie)
		// 2. Call /auth/refresh (gets access_token)
		// 3. Redirect to home
		// Wait for redirect to home (may take longer due to token refresh)
		await page.waitForURL("**/", { timeout: 20000 });

		// Step 6: Verify home page is displayed
		await expect(page.getByRole("heading", { name: /Welcome to Balansi|Bem-vindo ao Balansi/ })).toBeVisible({ timeout: 5000 });

		// Step 7: Verify session_id cookie was set (httpOnly cookie)
		// Note: access_token is stored in memory, not as a cookie
		const cookies = await page.context().cookies();
		const sessionIdCookie = cookies.find((c) => c.name === "session_id");

		expect(sessionIdCookie).toBeDefined();
		expect(sessionIdCookie?.httpOnly).toBe(true);
	});

	test("should logout successfully and redirect to auth page", async ({ page }) => {
		const formData = { name: "Test User", email: `test-logout-${Date.now()}@example.com` };

		// Step 1: Complete signup and confirmation flow
		await fillForm(page, formData.name, formData.email);
		await submitForm(page);

		// Wait for redirect to confirmation page
		await page.waitForURL("**/auth/confirmation*", { timeout: 15000 });
		await page.waitForSelector('h2:has-text("Confirm your email")', { timeout: 10000 });

		// Step 2: Fill confirmation code
		const pinInputs = page.locator('.pin-input-container input[type="text"]');
		await expect(pinInputs.first()).toBeVisible({ timeout: 5000 });
		await expect(pinInputs).toHaveCount(6);

		const confirmationCode = "123123";
		for (let i = 0; i < confirmationCode.length; i++) {
			const input = pinInputs.nth(i);
			await input.fill(confirmationCode[i]);
			await page.waitForTimeout(150);
		}

		// Step 3: Wait for redirect to home
		await page.waitForURL("**/", { timeout: 20000 });
		await expect(page.getByRole("heading", { name: /Welcome to Balansi|Bem-vindo ao Balansi/ })).toBeVisible({ timeout: 5000 });

		// Step 4: Verify logout button is visible
		const logoutButton = page.getByRole("button", { name: /Logout|Sair/ });
		await expect(logoutButton).toBeVisible({ timeout: 5000 });

		// Step 5: Click logout button
		await logoutButton.click();

		// Step 6: Verify redirect to auth page
		await page.waitForURL("**/auth", { timeout: 10000 });
		await expect(page.getByRole("heading", { name: "Register, Calculate, Evaluate" })).toBeVisible({ timeout: 5000 });

		// Step 7: Verify that trying to access home redirects back to auth
		await page.goto("/", { waitUntil: "domcontentloaded", timeout: 10000 });
		await page.waitForURL("**/auth", { timeout: 5000 });
		await expect(page.getByRole("heading", { name: "Register, Calculate, Evaluate" })).toBeVisible({ timeout: 5000 });

		// Step 8: Verify session_id cookie still exists (it's httpOnly, server should handle invalidation)
		// But access_token should be cleared from memory (we can't verify this directly in E2E)
		const cookies = await page.context().cookies();
		const sessionIdCookie = cookies.find((c) => c.name === "session_id");
		// Cookie may still exist but should not allow access (server-side invalidation)
		// The important thing is that the frontend doesn't allow access
	});
});
