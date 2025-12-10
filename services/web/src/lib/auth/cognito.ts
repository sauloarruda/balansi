import { browser } from "$app/environment";

/**
 * Cognito Hosted UI redirect utilities.
 *
 * These functions redirect users to AWS Cognito Hosted UI for authentication.
 * After authentication, Cognito redirects back to the callback endpoint with
 * an authorization code.
 */

/**
 * Redirect to Cognito Hosted UI for signup.
 *
 * @param professionalId - Optional professional ID to include in state parameter
 *
 * @example
 * ```typescript
 * redirectToSignup("123");
 * ```
 */
export function redirectToSignup(professionalId?: string): void {
	if (!browser) {
		console.warn("redirectToSignup called on server - skipping redirect");
		return;
	}

	const state = professionalId ? `professional_id=${professionalId}` : "";
	const url = getCognitoAuthUrl("signup", state);
	window.location.href = url;
}

/**
 * Redirect to Cognito Hosted UI for login.
 *
 * @param professionalId - Optional professional ID to include in state parameter
 *
 * @example
 * ```typescript
 * redirectToLogin("123");
 * ```
 */
export function redirectToLogin(professionalId?: string): void {
	if (!browser) {
		console.warn("redirectToLogin called on server - skipping redirect");
		return;
	}

	const state = professionalId ? `professional_id=${professionalId}` : "";
	const url = getCognitoAuthUrl("login", state);
	window.location.href = url;
}

/**
 * Build Cognito Hosted UI URL for authentication.
 *
 * @param action - Either "signup" or "login"
 * @param state - Optional state parameter (e.g., "professional_id=123")
 * @returns Complete Cognito Hosted UI URL
 *
 * @example
 * ```typescript
 * const url = getCognitoAuthUrl("login", "professional_id=123");
 * // Returns: https://domain.auth.region.amazoncognito.com/login?client_id=...&...
 * ```
 */
export function getCognitoAuthUrl(action: "signup" | "login", state: string): string {
	const domain = import.meta.env.VITE_COGNITO_DOMAIN;
	const clientId = import.meta.env.VITE_COGNITO_CLIENT_ID;
	const redirectUri = import.meta.env.VITE_COGNITO_REDIRECT_URI;

	if (!domain || !clientId || !redirectUri) {
		const missing = [];
		if (!domain) missing.push("VITE_COGNITO_DOMAIN");
		if (!clientId) missing.push("VITE_COGNITO_CLIENT_ID");
		if (!redirectUri) missing.push("VITE_COGNITO_REDIRECT_URI");

		throw new Error(
			`Missing required Cognito environment variables: ${missing.join(", ")}`
		);
	}

	// Ensure domain doesn't have trailing slash
	const cleanDomain = domain.replace(/\/$/, "");

	// Build base URL
	const baseUrl = `${cleanDomain}/${action}?`;

	// Build query parameters
	const params = new URLSearchParams({
		client_id: clientId,
		response_type: "code",
		redirect_uri: redirectUri,
		scope: "openid email profile", // Include 'profile' scope to get 'name' and 'preferred_username'
	});

	// Add state parameter if provided
	if (state) {
		params.append("state", state);
	}

	return baseUrl + params.toString();
}
