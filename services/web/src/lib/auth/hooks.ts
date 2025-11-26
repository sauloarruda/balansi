import { browser } from "$app/environment";
import { goto } from "$app/navigation";
import { hasSession } from "./session";

/**
 * Check if user is authenticated and redirect to home if they are
 * Performs async authentication check to allow token refresh via session cookie
 *
 * @returns Promise that resolves to true if user was redirected, false otherwise
 *
 * @example
 * ```svelte
 * <script lang="ts">
 * import { checkAuthAndRedirect } from "$lib/auth/hooks";
 *
 * let checking = $state(true);
 *
 * $effect(() => {
 *   if (browser) {
 *     checkAuthAndRedirect().then((redirected) => {
 *       if (!redirected) {
 *         checking = false;
 *       }
 *     });
 *   }
 * });
 * </script>
 * ```
 */
export async function checkAuthAndRedirect(): Promise<boolean> {
	if (!browser) {
		return false;
	}

	const isAuth = await hasSession();

	if (isAuth) {
		// Already authenticated, redirect to home
		goto("/");
		return true;
	}

	return false;
}
