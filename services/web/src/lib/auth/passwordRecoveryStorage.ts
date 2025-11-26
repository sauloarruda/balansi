/**
 * Temporary password recovery data keys (cleared after password reset)
 */
const PASSWORD_RECOVERY_DATA_KEYS = {
	EMAIL: "password_recovery_email",
	DESTINATION: "password_recovery_destination",
} as const;

/**
 * Password recovery data interface
 */
export interface PasswordRecoveryData {
	email: string;
	destination: string;
}

/**
 * Password recovery data storage (temporary, cleared after password reset)
 *
 * Note: This is used only for passing data between the forgot-password page and
 * the reset-password page. The email is stored so the user doesn't have to re-enter it,
 * and the destination (masked email) is stored to show where the code was sent.
 */
export const passwordRecoveryData = {
	save(email: string, destination: string): void {
		if (typeof window === "undefined") return;
		localStorage.setItem(PASSWORD_RECOVERY_DATA_KEYS.EMAIL, email);
		localStorage.setItem(PASSWORD_RECOVERY_DATA_KEYS.DESTINATION, destination);
	},

	get(): PasswordRecoveryData | null {
		if (typeof window === "undefined") return null;

		const email = localStorage.getItem(PASSWORD_RECOVERY_DATA_KEYS.EMAIL);
		const destination = localStorage.getItem(PASSWORD_RECOVERY_DATA_KEYS.DESTINATION);

		if (!email || !destination) return null;

		return {
			email,
			destination,
		};
	},

	clear(): void {
		if (typeof window === "undefined") return;
		localStorage.removeItem(PASSWORD_RECOVERY_DATA_KEYS.EMAIL);
		localStorage.removeItem(PASSWORD_RECOVERY_DATA_KEYS.DESTINATION);
	},
};

