<script lang="ts">
	import { browser } from "$app/environment";
	import { goto } from "$app/navigation";
	import type { ForgotPasswordRequest } from "$lib/api";
	import { api, ApiError, NetworkError } from "$lib/api";
	import { getAuthData, saveAuthData } from "$lib/auth/authStorage";
	import { checkAuthAndRedirect } from "$lib/auth/hooks";
	import { passwordRecoveryData } from "$lib/auth/passwordRecoveryStorage";
	import Button from "$lib/components/ds/Button.svelte";
	import Container from "$lib/components/ds/Container.svelte";
	import Input from "$lib/components/ds/Input.svelte";
	import { _ } from "$lib/i18n";
	import { isValidEmail } from "$lib/utils/validation";

	let checking = $state(true);
	let email = $state("");
	let submitting = $state(false);
	let error = $state<string | null>(null);

	// Check authentication and redirect if already logged in
	$effect(() => {
		if (browser) {
			checkAuthAndRedirect().then((redirected) => {
				if (!redirected) {
					// Not redirected, load saved email
					const authData = getAuthData();
					if (authData?.email) {
						email = authData.email;
					}
					checking = false;
				}
			});
		}
	});

	// Validation state
	let emailValid = $state(false);

	// Computed: form is valid when email is valid
	$effect(() => {
		emailValid = isValidEmail(email);
	});

	const isFormValid = $derived(emailValid);

	async function handleSubmit(e: SubmitEvent) {
		e.preventDefault();
		submitting = true;
		error = null;

		try {
			const request: ForgotPasswordRequest = { email };
			const response = await api.auth.forgotPassword({ forgotPasswordRequest: request });

			// Save email for reuse in other auth flows
			saveAuthData({ email });

			// Save email and destination for the reset-password page
			passwordRecoveryData.save(email, response.destination || email);

			// Redirect to reset-password page
			goto("/auth/reset-password");
		} catch (err) {
			if (err instanceof ApiError) {
				// API error already translated
				error = err.message;
			} else if (err instanceof NetworkError) {
				// Network error
				error = err.message;
			} else {
				// Unknown error
				error = $_("auth.forgotPassword.errors.connectionError");
			}
		} finally {
			submitting = false;
		}
	}

	function handleBackToLogin() {
		goto("/auth");
	}
</script>

<Container loading={checking}>
	{#snippet children()}
		{#if !checking}
			<h2 class="text-xl font-semibold mb-6 text-center">
				{$_("auth.forgotPassword.title")}
			</h2>

			<p class="text-center mb-6 text-gray-600 dark:text-gray-400">
				{$_("auth.forgotPassword.description")}
			</p>

			{#if error}
				<div class="error-message mb-4">{error}</div>
			{/if}

			<form onsubmit={handleSubmit} class="flex flex-col gap-6 my-8">
				<div class="relative">
					<Input
						type="email"
						id="email"
						name="email"
						label={$_("auth.forgotPassword.fields.email.label")}
						placeholder={$_("auth.forgotPassword.fields.email.placeholder")}
						required
						errorMessage={$_("auth.signup.fields.email.error")}
						bind:value={email}
						disabled={submitting}
					/>
				</div>
				<Button type="submit" loading={submitting} disabled={submitting || !isFormValid}>
					{$_("auth.forgotPassword.submit")}
				</Button>
			</form>

			<div class="text-center">
				<button
					type="button"
					class="text-sm text-blue-600 hover:text-blue-800 dark:text-blue-400 dark:hover:text-blue-300"
					onclick={handleBackToLogin}
					disabled={submitting}
				>
					{$_("auth.forgotPassword.backToLogin")}
				</button>
			</div>
		{/if}
	{/snippet}
</Container>
