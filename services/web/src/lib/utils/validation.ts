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

/**
 * Password requirement checks
 */
export interface PasswordRequirements {
	minLength: boolean;
	hasUppercase: boolean;
	hasLowercase: boolean;
	hasNumber: boolean;
	hasSpecial: boolean;
}

/**
 * Validates if a password meets all security requirements
 * Requirements: Min 8 chars, uppercase, lowercase, number, special char
 * @param password The password string to validate
 * @returns true if all requirements are met, false otherwise
 */
export function isValidPassword(password: string): boolean {
	if (!password || typeof password !== "string") return false;

	const requirements = getPasswordRequirements(password);
	return Object.values(requirements).every(req => req === true);
}

/**
 * Gets detailed password requirements status
 * @param password The password string to check
 * @returns Object with boolean flags for each requirement
 */
export function getPasswordRequirements(password: string): PasswordRequirements {
	if (!password || typeof password !== "string") {
		return {
			minLength: false,
			hasUppercase: false,
			hasLowercase: false,
			hasNumber: false,
			hasSpecial: false
		};
	}

	return {
		minLength: password.length >= 8,
		hasUppercase: /[A-Z]/.test(password),
		hasLowercase: /[a-z]/.test(password),
		hasNumber: /\d/.test(password),
		hasSpecial: /[!@#$%^&*()_+\-=[\]{};':"\\|,.<>/?]/.test(password)
	};
}

/**
 * Gets array of unmet password requirements as error message keys
 * @param password The password string to check
 * @returns Array of i18n keys for unmet requirements
 */
export function getPasswordErrors(password: string): string[] {
	const requirements = getPasswordRequirements(password);
	const errors: string[] = [];

	if (!requirements.minLength) errors.push("auth.resetPassword.requirements.minLength");
	if (!requirements.hasUppercase) errors.push("auth.resetPassword.requirements.uppercase");
	if (!requirements.hasLowercase) errors.push("auth.resetPassword.requirements.lowercase");
	if (!requirements.hasNumber) errors.push("auth.resetPassword.requirements.number");
	if (!requirements.hasSpecial) errors.push("auth.resetPassword.requirements.special");

	return errors;
}
