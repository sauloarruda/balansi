/**
 * Session management for client-side authentication
 *
 * The session_id is stored as an httpOnly cookie by the server.
 * We don't need to manage it directly - it's sent automatically with requests.
 *
 * This module now focuses on checking if a session exists by attempting
 * to get an access token (which requires a valid session_id cookie).
 */

import { getAccessToken, hasAccessToken } from "./token";

/**
 * Check if user has a valid session
 * This checks if we can get an access token (which requires session_id cookie)
 */
export async function hasSession(): Promise<boolean> {
	const token = await getAccessToken();
	return token !== null;
}

/**
 * Check if user has a valid session (synchronous check)
 * Only checks if we have a token in memory, doesn't refresh
 */
export function hasSessionSync(): boolean {
	return hasAccessToken();
}
