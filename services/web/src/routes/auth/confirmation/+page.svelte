<script lang="ts">
	import { browser } from "$app/environment";
	import { enhance } from "$app/forms";
	import { goto } from "$app/navigation";
	import { signupData } from "$lib/auth/signupStorage";
	import Button from "$lib/components/ds/Button.svelte";
	import Container from "$lib/components/ds/Container.svelte";
	import PinInput from "$lib/components/ds/PinInput.svelte";
	import { _ } from "$lib/i18n";
	import type { PageData } from "./$types";

	let { data }: { data: PageData } = $props();

	let loading = $state(true);
	let name = $state("");
	let email = $state("");
	let userId = $state<number | null>(null);
	let confirmationCode = $state("");
	let submitting = $state(false);
	let error = $state<string | null>(null);
	let pinError = $state(false);

	// Check authentication and signup data
	$effect(() => {
		if (data.authenticated) {
			// Already authenticated, redirect to home
			goto("/");
			return;
		}

		if (!browser) {
			loading = false;
			return;
		}

		// Get signup data from localStorage
		const signup = signupData.get();
		if (!signup) {
			// Missing signup data, redirect to signup
			goto("/auth");
			return;
		}

		userId = signup.userId;
		name = signup.name;
		email = signup.email;
		loading = false;
	});

	// Focus PIN input when page loads
	$effect(() => {
		if (!loading && browser && !submitting) {
			// Small delay to ensure PinInput is rendered
			setTimeout(() => {
				const firstInput = document.querySelector(
					'input[aria-label="PIN digit 1"]'
				) as HTMLInputElement;
				if (firstInput && !firstInput.disabled) {
					firstInput.focus();
				}
			}, 100);
		}
	});
</script>

<Container {loading}>
	{#snippet children()}
		{#if !loading}
			<h2 class="text-xl font-semibold mb-6 text-center">
				{$_("auth.confirmation.title")}
			</h2>
			<p class="text-center mb-6">
				{$_("auth.confirmation.description", { values: { name, email } })}
			</p>
			{#if error}
				<div class="error-message mb-4">{error}</div>
			{/if}

			<form
				method="POST"
				action="?/confirm"
				use:enhance={({ formData, cancel }) => {
					submitting = true;
					error = null;
					pinError = false;

					return async ({ result, update }) => {
						submitting = false;

						if (result.type === "redirect") {
							// Server redirected - clear signup data
							// The redirect will happen automatically, but we need to clear localStorage
							signupData.clear();
							// Let SvelteKit handle the redirect automatically
							await update();
							return;
						}

						if (result.type === "success") {
							// This shouldn't happen if redirect is working, but handle it anyway
							signupData.clear();
							if (browser) {
								window.location.href = "/";
							}
						} else if (result.type === "failure" && result.data) {
							const data = result.data as { error?: string; code?: string };
							pinError = true;
							error = data.error || $_("auth.confirmation.errors.connectionError");
							await update();
						}
					};
				}}
				class="flex flex-col gap-6 my-8"
			>
				<input type="hidden" name="userId" value={userId || ""} />
				<input type="hidden" name="code" value={confirmationCode} />
				<div class="flex flex-col gap-2">
					<label for="confirmation-code" class="text-sm font-medium text-gray-700 text-center">
						{$_("auth.confirmation.code.label")}
					</label>
					<PinInput
						length={6}
						bind:value={confirmationCode}
						disabled={submitting}
						error={pinError}
						errorMessage={error || ""}
						onComplete={(code) => {
							confirmationCode = code;
							// Auto-submit when code is complete
							if (code.length === 6 && userId && !submitting) {
								const form = document.querySelector('form[action="?/confirm"]') as HTMLFormElement;
								if (form) {
									// Update hidden input
									const codeInput = form.querySelector('input[name="code"]') as HTMLInputElement;
									if (codeInput) {
										codeInput.value = code;
									}
									form.requestSubmit();
								}
							}
						}}
						onChange={(code) => {
							confirmationCode = code;
							// Update hidden input
							const form = document.querySelector('form[action="?/confirm"]') as HTMLFormElement;
							if (form) {
								const codeInput = form.querySelector('input[name="code"]') as HTMLInputElement;
								if (codeInput) {
									codeInput.value = code;
								}
							}
							// Clear error when user starts typing
							if (error) {
								error = null;
								pinError = false;
							}
						}}
					/>
				</div>
				{#if error && !pinError}
					<div class="error-message text-center text-sm text-red-600">{error}</div>
				{/if}
				<Button
					type="submit"
					loading={submitting}
					disabled={submitting || confirmationCode.length !== 6}
				>
					{$_("common.confirm")}
				</Button>
			</form>
		{/if}
	{/snippet}
</Container>
