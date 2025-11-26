/**
 * Shared authentication data storage for temporary auth flows
 * Used across signup, login, forgot-password, confirmation, etc.
 *
 * This stores user data to improve UX by pre-filling forms and
 * passing data between auth pages.
 *
 * Data structure:
 * - email: always saved (used in all auth flows)
 * - name: saved during signup (optional)
 * - userId: saved during signup for confirmation (optional)
 */

const AUTH_STORAGE_KEY = "auth_temp_data";

export interface AuthData {
	email: string;
	name?: string;
	userId?: number;
}

/**
 * Save authentication data to localStorage
 * Can save just email, or email + name, or email + name + userId
 *
 * @param data - Authentication data to save
 *
 * @example
 * // Just email (login/forgot-password)
 * saveAuthData({ email: "user@example.com" });
 *
 * // Email + name (signup)
 * saveAuthData({ email: "user@example.com", name: "John" });
 *
 * // Email + name + userId (signup pending confirmation)
 * saveAuthData({ email: "user@example.com", name: "John", userId: 123 });
 */
export function saveAuthData(data: AuthData): void {
	if (typeof window === "undefined") return;
	if (!data.email) return;

	localStorage.setItem(AUTH_STORAGE_KEY, JSON.stringify(data));
}

/**
 * Get saved authentication data from localStorage
 * @returns Saved auth data or null if not found
 */
export function getAuthData(): AuthData | null {
	if (typeof window === "undefined") return null;

	const stored = localStorage.getItem(AUTH_STORAGE_KEY);
	if (!stored) return null;

	try {
		return JSON.parse(stored) as AuthData;
	} catch {
		return null;
	}
}

/**
 * Clear saved authentication data from localStorage
 * Should be called after successful login/signup completion
 */
export function clearAuthData(): void {
	if (typeof window === "undefined") return;

	localStorage.removeItem(AUTH_STORAGE_KEY);
}

/**
 * Legacy helper: Get just the email from auth data
 * @deprecated Use getAuthData() instead
 */
export function getSavedEmail(): string | null {
	const data = getAuthData();
	return data?.email || null;
}

/**
 * Legacy helper: Save just the email
 * @deprecated Use saveAuthData({ email }) instead
 */
export function saveEmail(email: string): void {
	saveAuthData({ email });
}
