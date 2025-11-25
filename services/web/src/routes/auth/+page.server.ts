import { isAuthenticated } from "$lib/auth/serverAuth";
import type { PageServerLoad } from "./$types";

export const load: PageServerLoad = async ({ cookies }) => {
	return {
		authenticated: isAuthenticated(cookies),
	};
};
