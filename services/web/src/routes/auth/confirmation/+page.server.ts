import { createApiConfig } from "$lib/api";
import { AuthenticationApi, ResponseError } from "$lib/api/generated";
import { isAuthenticated, setAuthCookies } from "$lib/auth/serverAuth";
import { fail, redirect } from "@sveltejs/kit";
import type { Actions, PageServerLoad } from "./$types";

export const load: PageServerLoad = async ({ cookies }) => {
	return {
		authenticated: isAuthenticated(cookies),
	};
};

export const actions: Actions = {
	confirm: async ({ request, cookies }) => {
		const data = await request.formData();
		const userId = data.get("userId");
		const code = data.get("code");

		// Validate inputs
		if (!userId || !code) {
			return fail(400, {
				error: "User ID and code are required",
			});
		}

		try {
			// Initialize API client
			const config = createApiConfig(fetch); // Use global fetch available in Node 18+
			const authApi = new AuthenticationApi(config);

			// Call Go API using generated client
			const tokens = await authApi.confirmSignUp({
				confirmRequest: {
					userId: parseInt(userId as string, 10),
					code: code as string,
				},
			});

			console.log("Tokens received:", {
				hasAccessToken: !!tokens.accessToken,
				hasRefreshToken: !!tokens.refreshToken,
				hasIdToken: !!tokens.idToken,
				expiresIn: tokens.expiresIn,
				tokenType: tokens.tokenType,
			});

			// Validate tokens exist
			if (!tokens.accessToken || !tokens.refreshToken || !tokens.idToken) {
				console.error("Missing tokens in response");
				return fail(500, {
					error: "Invalid token response from server",
				});
			}

			// Set auth cookies
			setAuthCookies(cookies, tokens);

			console.log("Cookies set successfully");

			// Redirect to home - this ensures cookies are sent with the redirect response
			throw redirect(302, "/");
		} catch (error) {
			// SvelteKit redirect throws an error, so we need to re-throw it
			if (error && typeof error === "object" && "status" in error && "location" in error) {
				throw error; // Re-throw redirect
			}

			// Handle API errors
			if (error instanceof ResponseError) {
				const response = error.response;
				let message = "Confirmation failed";
				let code = "unknown_error";

				try {
					const data = await response.json();
					message = data.message || message;
					code = data.code || code;
				} catch (e) {
					// Could not parse error response
				}

				return fail(response.status, {
					error: message,
					code: code,
					success: false,
				});
			}

			// Log actual error for debugging
			console.error("Confirmation error:", error);
			const errorMessage =
				error instanceof Error ? error.message : "Failed to connect to server";
			return fail(500, {
				error: errorMessage,
				code: "server_error",
				success: false,
			});
		}
	},
};
