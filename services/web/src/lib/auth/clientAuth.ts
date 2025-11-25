/**
 * Client-side authentication helpers
 *
 * Uses access_token stored in memory for authentication.
 * The session_id cookie (httpOnly) is used to refresh the access_token when needed.
 */

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
 * Logout by clearing access token
 * Sets a flag to prevent automatic token refresh after logout
 * The session_id cookie will be cleared by the server on next request if needed
 */
export async function logout(): Promise<void> {
	clearAccessToken(true); // Pass true to indicate this is a logout
}
