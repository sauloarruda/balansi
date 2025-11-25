/**
 * Validates if a string is a valid email address
 * @param email The email string to validate
 * @returns true if valid, false otherwise
 */
export function isValidEmail(email: string): boolean {
	if (!email || typeof email !== "string") return false;
	const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
	return emailRegex.test(email.trim());
}

/**
 * Validates if a name is valid (at least 2 characters)
 * @param name The name string to validate
 * @returns true if valid, false otherwise
 */
export function isValidName(name: string): boolean {
	if (!name || typeof name !== "string") return false;
	return name.trim().length >= 2;
}
