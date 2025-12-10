import { clearAccessToken, getAccessToken } from "$lib/auth/token";
import { _ } from "$lib/i18n";
import { translateApiError } from "$lib/i18n/helpers";
import { get } from "svelte/store";
import { AuthenticationApi, Configuration, FetchError, ResponseError } from "./generated";

/**
 * Custom API error with translated message
 */
export class ApiError extends Error {
	constructor(
		message: string,
		public status: number,
		public code?: string,
		public originalMessage?: string
	) {
		super(message);
		this.name = "ApiError";
	}
}

/**
 * Network/connection error
 */
export class NetworkError extends Error {
	constructor(message: string) {
		super(message);
		this.name = "NetworkError";
	}
}

/**
 * Get API base URL from environment
 */
export function getApiBaseUrl(): string {
	return import.meta.env.VITE_API_URL ?? "http://localhost:3000";
}

/**
 * Create API configuration
 * @param fetchImpl Optional fetch implementation. If not provided, uses default browser fetch.
 */
export function createApiConfig(fetchImpl?: typeof fetch): Configuration {
	return new Configuration({
		basePath: getApiBaseUrl(),
		fetchApi: fetchImpl || (async (url, options) => {
			// Skip auth for refresh endpoint to avoid infinite loop
			const isRefreshEndpoint = url.toString().includes("/auth/refresh");

			// Get access token and add to headers if available
			const headers = options?.headers
				? new Headers(options.headers)
				: new Headers();

			if (!isRefreshEndpoint) {
				const token = await getAccessToken();
				if (token) {
					headers.set("Authorization", `Bearer ${token}`);
				}
			}

			// Client-side: include credentials for cookies (session_id cookie)
			let response = await fetch(url, {
				...options,
				headers,
				credentials: "include", // Send/receive cookies automatically
			});

			// If we get 401, try to refresh token and retry once
			if (response.status === 401 && !isRefreshEndpoint) {
				clearAccessToken();
				const newToken = await getAccessToken();

				if (newToken) {
					// Retry the request with new token
					headers.set("Authorization", `Bearer ${newToken}`);
					response = await fetch(url, {
						...options,
						headers,
						credentials: "include",
					});
				}
			}

			// If we still get 401/403 after refresh attempt, clear token
			if (response.status === 401 || response.status === 403) {
				clearAccessToken();
			}

			return response;
		}),
	});
}

/**
 * Handle API errors and translate them
 */
async function handleApiError(error: unknown): Promise<never> {
	// Check if it's a ResponseError from the generated client
	if (error instanceof ResponseError && error.response) {
		const response = error.response;
		const status = response.status;

		// If we get 401/403, clear access token (unauthorized)
		// This will trigger refresh on next request
		if (status === 401 || status === 403) {
			clearAccessToken();
		}

		try {
			// Try to parse error response body
			const contentType = response.headers.get("content-type");
			if (contentType?.includes("application/json")) {
				const data = await response.json();
				if (data?.code) {
					const translatedMessage = translateApiError(data.code, data.message);
					throw new ApiError(translatedMessage, status, data.code, data.message);
				}
			}
			// If no JSON or no code, use generic error based on status
			if (status >= 500) {
				throw new ApiError(get(_)("errors.serverError"), status);
			} else {
				throw new ApiError(get(_)("errors.invalidRequest"), status);
			}
		} catch (e) {
			// If error is already ApiError, re-throw it
			if (e instanceof ApiError) {
				throw e;
			}
			// Otherwise, use generic error
			if (status >= 500) {
				throw new ApiError(get(_)("errors.serverError"), status);
			} else {
				throw new ApiError(get(_)("errors.invalidRequest"), status);
			}
		}
	}

	// Check if it's a FetchError (network error)
	if (error instanceof FetchError) {
		throw new NetworkError(get(_)("errors.serverError"));
	}

	// Unknown error - treat as network error
	throw new NetworkError(get(_)("errors.serverError"));
}

/**
 * Create a proxy wrapper that intercepts all API method calls
 * and applies error handling automatically
 */
function createApiProxy<T extends object>(apiInstance: T): T {
	return new Proxy(apiInstance, {
		get(target, prop, receiver) {
			const original = Reflect.get(target, prop, receiver);

			// If it's not a function, return as-is
			if (typeof original !== "function") {
				return original;
			}

			// Wrap the function to add error handling
			return async function (...args: unknown[]) {
				try {
					return await original.apply(target, args);
				} catch (error) {
					// If error is already our custom error, re-throw it
					if (error instanceof ApiError || error instanceof NetworkError) {
						throw error;
					}
					// Otherwise, handle and translate the error
					return await handleApiError(error);
				}
			};
		},
	});
}

/**
 * Create API instances with automatic error handling
 */
const authApiInstance = new AuthenticationApi(createApiConfig());

/**
 * Wrapped API client with automatic error handling and i18n integration
 *
 * All methods from the generated API are available directly.
 * The Proxy automatically handles errors and translates them via i18n.
 *
 * Usage:
 *   api.auth.signUp({ signupRequest: { name, email } })
 */
export const api = {
	/**
	 * Authentication API with automatic error handling
	 * All methods are intercepted by Proxy and errors are automatically translated
	 */
	auth: createApiProxy(authApiInstance),
} as {
	auth: AuthenticationApi;
};
