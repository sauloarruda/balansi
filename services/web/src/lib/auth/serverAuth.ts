/**
 * Server-side authentication helpers
 *
 * Since we're using httpOnly cookies, tokens cannot be read in the client.
 * Use these helpers in server-side code (+page.server.ts, +layout.server.ts, hooks.server.ts)
 */

import type { TokenResponse } from "$lib/api/generated";
import type { Cookies } from "@sveltejs/kit";

const ACCESS_TOKEN_EXPIRY = 3600; // 1 hour in seconds
const REFRESH_TOKEN_EXPIRY = 7 * 24 * 60 * 60; // 7 days in seconds

/**
 * Check if user is authenticated via cookies
 */
export function isAuthenticated(cookies: Cookies): boolean {
	const accessToken = cookies.get("access_token");
	const refreshToken = cookies.get("refresh_token");
	return !!(accessToken && refreshToken);
}

/**
 * Get access token from cookies (server-side only)
 */
export function getAccessToken(cookies: Cookies): string | null {
	return cookies.get("access_token") || null;
}

/**
 * Get refresh token from cookies (server-side only)
 */
export function getRefreshToken(cookies: Cookies): string | null {
	return cookies.get("refresh_token") || null;
}

/**
 * Get ID token from cookies (server-side only)
 */
export function getIdToken(cookies: Cookies): string | null {
	return cookies.get("id_token") || null;
}

/**
 * Clear authentication cookies
 */
export function clearAuthCookies(cookies: Cookies): void {
	cookies.delete("access_token", { path: "/" });
	cookies.delete("refresh_token", { path: "/" });
	cookies.delete("id_token", { path: "/" });
}

/**
 * Set authentication cookies
 */
export function setAuthCookies(cookies: Cookies, tokens: TokenResponse): void {
	// Set httpOnly cookies
	// In development (HTTP), secure must be false
	// In production (HTTPS), secure should be true
	const isProduction = process.env.NODE_ENV === "production";

	// Cognito default expiration times:
	// - Access Token: 1 hour (3600 seconds)
	// - ID Token: 1 hour (3600 seconds) - same as access token
	// - Refresh Token: 30 days (but we'll use 7 days for security)
	// If expiresIn is 0 (cognito-local may return 0), use defaults
	const accessTokenExpiresIn =
		tokens.expiresIn > 0 ? tokens.expiresIn : ACCESS_TOKEN_EXPIRY;
	const refreshTokenExpiresIn = REFRESH_TOKEN_EXPIRY;

	const cookieOptions = {
		httpOnly: true,
		secure: isProduction, // HTTPS only in production
		sameSite: (isProduction ? "strict" : "lax") as "strict" | "lax", // CSRF protection
		path: "/",
	};

	console.log("Setting cookies:", {
		accessToken: tokens.accessToken ? "present" : "missing",
		refreshToken: tokens.refreshToken ? "present" : "missing",
		idToken: tokens.idToken ? "present" : "missing",
		expiresIn: tokens.expiresIn,
		accessTokenMaxAge: accessTokenExpiresIn,
		refreshTokenMaxAge: refreshTokenExpiresIn,
		cookieOptions,
	});

	// Access token and ID token expire together (typically 1 hour)
	cookies.set("access_token", tokens.accessToken, {
		...cookieOptions,
		maxAge: accessTokenExpiresIn,
	});

	cookies.set("id_token", tokens.idToken, {
		...cookieOptions,
		maxAge: accessTokenExpiresIn, // Same expiration as access token
	});

	// Refresh token lasts longer (7 days)
	cookies.set("refresh_token", tokens.refreshToken, {
		...cookieOptions,
		maxAge: refreshTokenExpiresIn,
	});
}
