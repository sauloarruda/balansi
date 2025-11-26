/**
 * Focus utilities for form elements
 */

/**
 * Focus the first PIN input field
 * Used after rendering PIN input components to improve UX
 *
 * @param delay - Delay in milliseconds before focusing (default: 100ms)
 *
 * @example
 * ```svelte
 * <script>
 * import { focusPinInput } from "$lib/utils/focus";
 *
 * $effect(() => {
 *   if (!loading && !submitting) {
 *     focusPinInput();
 *   }
 * });
 * </script>
 * ```
 */
export function focusPinInput(delay = 100): void {
	if (typeof window === "undefined") return;

	window.setTimeout(() => {
		const firstInput = document.querySelector(
			'input[aria-label="PIN digit 1"]'
		) as HTMLInputElement;

		if (firstInput && !firstInput.disabled) {
			firstInput.focus();
		}
	}, delay);
}
