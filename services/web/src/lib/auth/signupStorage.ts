/**
 * Temporary signup data keys (cleared after confirmation)
 */
const SIGNUP_DATA_KEYS = {
	USER_ID: "signup_user_id",
	NAME: "signup_name",
	EMAIL: "signup_email",
} as const;

/**
 * Signup data storage (temporary, cleared after confirmation)
 *
 * Note: This is used only for passing data between the signup page and
 * the confirmation page. Authentication tokens are handled via httpOnly cookies.
 */
export const signupData = {
	save(userId: number, name: string, email: string): void {
		if (typeof window === "undefined") return;
		localStorage.setItem(SIGNUP_DATA_KEYS.USER_ID, userId.toString());
		localStorage.setItem(SIGNUP_DATA_KEYS.NAME, name);
		localStorage.setItem(SIGNUP_DATA_KEYS.EMAIL, email);
	},

	get(): { userId: number; name: string; email: string } | null {
		if (typeof window === "undefined") return null;

		const userId = localStorage.getItem(SIGNUP_DATA_KEYS.USER_ID);
		const name = localStorage.getItem(SIGNUP_DATA_KEYS.NAME);
		const email = localStorage.getItem(SIGNUP_DATA_KEYS.EMAIL);

		if (!userId || !name || !email) return null;

		return {
			userId: parseInt(userId, 10),
			name,
			email,
		};
	},

	clear(): void {
		if (typeof window === "undefined") return;
		localStorage.removeItem(SIGNUP_DATA_KEYS.USER_ID);
		localStorage.removeItem(SIGNUP_DATA_KEYS.NAME);
		localStorage.removeItem(SIGNUP_DATA_KEYS.EMAIL);
	},
};
