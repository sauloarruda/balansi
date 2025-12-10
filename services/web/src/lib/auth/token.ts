/**
 * Access token management
 *
 * Manages access_token in memory with automatic refresh using httpOnly cookie.
 * The bal_session_id cookie is set by the server (httpOnly) and used to refresh tokens.
 * The cookie contains encrypted session data (refresh token + user ID) that the backend
 * uses to refresh the access token.
 */

import { browser } from "$app/environment";
import { getApiBaseUrl } from "$lib/api";

// In-memory access token storage
let accessToken: string | null = null;
let tokenExpiresAt: number | null = null; // Timestamp in milliseconds
let logoutFlag: boolean = false; // Flag to prevent automatic refresh after logout

// Token expiry buffer - configurable via environment variable
// Default: 5 minutes (5 * 60 * 1000 ms)
// Can be overridden with VITE_TOKEN_EXPIRY_BUFFER_MINUTES environment variable
function getTokenExpiryBuffer(): number {
	const bufferMinutes = import.meta.env.VITE_TOKEN_EXPIRY_BUFFER_MINUTES;
	if (bufferMinutes) {
		const parsed = parseInt(bufferMinutes, 10);
		if (!isNaN(parsed) && parsed > 0) {
			return parsed * 60 * 1000; // Convert minutes to milliseconds
		}
	}
	return 5 * 60 * 1000; // Default: 5 minutes
}

const TOKEN_EXPIRY_BUFFER = getTokenExpiryBuffer();

/**
 * Get access token, refreshing if necessary
 * Returns null if refresh fails
 */
export async function getAccessToken(): Promise<string | null> {
	// If user explicitly logged out, don't try to refresh
	if (logoutFlag) {
		return null;
	}

	// Check if we have a valid token
	if (accessToken && tokenExpiresAt && Date.now() < tokenExpiresAt - TOKEN_EXPIRY_BUFFER) {
		return accessToken;
	}

	// Token expired or doesn't exist, try to refresh
	return await refreshAccessToken();
}

/**
 * Refresh access token using httpOnly cookie (bal_session_id)
 * Returns the new access token or null if refresh fails
 */
export async function refreshAccessToken(): Promise<string | null> {
	if (!browser) {
		return null;
	}

	try {
		const apiUrl = getApiBaseUrl();
		const response = await fetch(`${apiUrl}/auth/refresh`, {
			method: "POST",
			credentials: "include", // Include bal_session_id cookie (httpOnly)
		});

		if (response.ok) {
			const data = await response.json();

			// Backend returns snake_case: { access_token, expires_in, token_type }
			// Support both snake_case (from backend) and camelCase (for backward compatibility)
			const token = data.access_token || data.accessToken;
			const expiresIn = data.expires_in !== undefined ? data.expires_in : data.expiresIn;

			// Note: expiresIn can be 0 (cognito-local returns 0), so we check for !== undefined
			if (token && typeof expiresIn === "number") {
				// Clear logout flag when we successfully refresh (user is logging in again)
				logoutFlag = false;
				setAccessToken(token, expiresIn);
				return token;
			} else {
				console.error("refreshAccessToken: Missing access_token or invalid expires_in in response", data);
			}
		} else {
			const errorText = await response.text();
			console.error("refreshAccessToken: Response not OK", response.status, errorText);
		}

		// Refresh failed - clear token
		clearAccessToken();
		return null;
	} catch (error) {
		console.error("refreshAccessToken: Error refreshing access token:", error);
		clearAccessToken();
		return null;
	}
}

/**
 * Set access token with expiration
 * @param token The access token
 * @param expiresIn Expiration time in seconds (0 means token expires immediately)
 */
export function setAccessToken(token: string, expiresIn: number): void {
	accessToken = token;
	// Convert expiresIn (seconds) to timestamp (milliseconds)
	// If expiresIn is 0, set a very short expiration (1 minute) to avoid immediate expiration
	// This handles cognito-local which returns 0 for expiresIn
	const expiresInMs = expiresIn > 0 ? expiresIn * 1000 : 60 * 1000; // Default to 1 minute if 0
	tokenExpiresAt = Date.now() + expiresInMs;
}

/**
 * Clear access token from memory
 * @param isLogout If true, sets a flag to prevent automatic refresh after logout
 */
export function clearAccessToken(isLogout: boolean = false): void {
	accessToken = null;
	tokenExpiresAt = null;
	logoutFlag = isLogout;
}

/**
 * Check if we have a valid access token (without refreshing)
 */
export function hasAccessToken(): boolean {
	return accessToken !== null && tokenExpiresAt !== null && Date.now() < tokenExpiresAt;
}
