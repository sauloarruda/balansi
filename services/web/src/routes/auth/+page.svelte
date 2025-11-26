<script lang="ts">
	import { browser } from "$app/environment";
	import { goto } from "$app/navigation";
	import type { SignupRequest } from "$lib/api";
	import { api, ApiError, NetworkError } from "$lib/api";
	import { getAuthData, saveAuthData } from "$lib/auth/authStorage";
	import { checkAuthAndRedirect } from "$lib/auth/hooks";
	import Button from "$lib/components/ds/Button.svelte";
	import Container from "$lib/components/ds/Container.svelte";
	import Input from "$lib/components/ds/Input.svelte";
	import { _ } from "$lib/i18n";
	import { isValidEmail, isValidName } from "$lib/utils/validation";

	let checking = $state(true);
	let name = $state("");
	let email = $state("");
	let submitting = $state(false);
	let error = $state<string | null>(null);

	// Validation states
	let nameValid = $state(false);
	let emailValid = $state(false);

	// Computed: form is valid when both fields are valid
	$effect(() => {
		// Validate name
		nameValid = isValidName(name);

		// Validate email
		emailValid = isValidEmail(email);
	});

	const isFormValid = $derived(nameValid && emailValid);

	// Check authentication and redirect if already logged in
	$effect(() => {
		if (browser) {
			checkAuthAndRedirect().then((redirected) => {
				if (!redirected) {
					// Not redirected, load saved data
					const savedData = getAuthData();
					if (savedData) {
						email = savedData.email;
						if (savedData.name) {
							name = savedData.name;
						}
					}
					checking = false;
				}
			});
		}
	});

	async function handleSubmit(e: SubmitEvent) {
		e.preventDefault();
		submitting = true;
		error = null;

		try {
			const request: SignupRequest = { name, email };
			const response = await api.auth.signUp({ signupRequest: request });

			if (response.status === "pending_confirmation") {
				// Save auth data (email + name + userId) for confirmation page
				saveAuthData({
					email: response.email,
					name: response.name,
					userId: response.id,
				});

				// Redirect to confirmation page
				goto("/auth/confirmation");
			} else {
				// User created successfully
				// TODO: Handle success case
			}
		} catch (err) {
			if (err instanceof ApiError) {
				// API error already translated
				error = err.message;
				// TODO: Redirect to login page if user_exists (err.code === "user_exists")
			} else if (err instanceof NetworkError) {
				// Network error
				error = err.message;
			} else {
				// Unknown error
				error = $_("auth.signup.errors.connectionError");
			}
		} finally {
			submitting = false;
		}
	}
</script>

<Container loading={checking}>
	{#snippet children()}
		{#if !checking}
			<h2 class="text-xl font-semibold mb-6 text-center">
				{$_("auth.signup.title")}
			</h2>

			<p class="text-center mb-6">
				{$_("auth.signup.description")}
			</p>

			{#if error}
				<div class="error-message mb-4">{error}</div>
			{/if}

			<form onsubmit={handleSubmit} class="flex flex-col gap-6 my-8">
				<div class="relative">
					<Input
						type="text"
						id="name"
						name="name"
						label={$_("auth.signup.fields.name.label")}
						placeholder={$_("auth.signup.fields.name.placeholder")}
						required
						minlength={2}
						errorMessage={$_("auth.signup.fields.name.error")}
						bind:value={name}
						disabled={submitting}
					/>
				</div>
				<div class="relative">
					<Input
						type="email"
						id="email"
						name="email"
						label={$_("auth.signup.fields.email.label")}
						placeholder={$_("auth.signup.fields.email.placeholder")}
						required
						errorMessage={$_("auth.signup.fields.email.error")}
						bind:value={email}
						disabled={submitting}
					/>
				</div>
				<Button type="submit" loading={submitting} disabled={submitting || !isFormValid}>
					{$_("common.continue")}
				</Button>
			</form>

			<div class="text-center mt-4">
				<a
					href="/auth/forgot-password"
					class="text-sm text-blue-600 hover:text-blue-800 dark:text-blue-400 dark:hover:text-blue-300"
				>
					{$_("auth.forgotPassword.title")}
				</a>
			</div>
		{/if}
	{/snippet}
</Container>
