/**
 * Client-side authentication helpers
 *
 * Uses access_token stored in memory for authentication.
 * The session_id cookie (httpOnly) is used to refresh the access_token when needed.
 */

import { api } from "$lib/api";
import { hasSessionSync } from "./session";
import { clearAccessToken } from "./token";

/**
 * Check if user is authenticated
 * Checks if we have a valid access token (synchronous check)
 */
export function checkAuth(): boolean {
	return hasSessionSync();
}

/**
 * Logout by clearing access token and session cookie
 * Calls the backend to invalidate the session_id cookie
 */
export async function logout(): Promise<void> {
	// Clear access token from memory first
	clearAccessToken(true); // Pass true to indicate this is a logout

	// Call backend to clear session_id cookie using generated API client
	try {
		await api.auth.logout();
	} catch (error) {
		// Ignore errors - we already cleared the token locally
		console.error("Logout error (ignored):", error);
	}
}
