import { clearAuthCookies, isAuthenticated } from "$lib/auth/serverAuth";
import { redirect } from "@sveltejs/kit";
import type { Actions, PageServerLoad } from "./$types";

export const load: PageServerLoad = async ({ cookies }) => {
	return {
		authenticated: isAuthenticated(cookies),
	};
};

export const actions: Actions = {
	logout: async ({ cookies }) => {
		// Clear authentication cookies
		clearAuthCookies(cookies);
		// Redirect to auth page
		throw redirect(302, "/auth");
	},
};
