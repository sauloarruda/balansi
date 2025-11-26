<script lang="ts">
	import { browser } from "$app/environment";
	import { goto } from "$app/navigation";
	import { api, ApiError, NetworkError } from "$lib/api";
	import { clearAuthData, getAuthData } from "$lib/auth/authStorage";
	import { checkAuthAndRedirect } from "$lib/auth/hooks";
	import { refreshAccessToken } from "$lib/auth/token";
	import Button from "$lib/components/ds/Button.svelte";
	import Container from "$lib/components/ds/Container.svelte";
	import PinInput from "$lib/components/ds/PinInput.svelte";
	import { _ } from "$lib/i18n";

	let _checking = $state(true);
	let loading = $state(true);
	let name = $state("");
	let email = $state("");
	let userId = $state<number | null>(null);
	let confirmationCode = $state("");
	let submitting = $state(false);
	let error = $state<string | null>(null);
	let pinError = $state(false);

	// Check authentication and load auth data
	$effect(() => {
		if (browser) {
			checkAuthAndRedirect().then((redirected) => {
				if (!redirected) {
					_checking = false;

					// Get auth data from localStorage
					const authData = getAuthData();
					if (!authData || !authData.userId || !authData.name) {
						// Missing required data, redirect to signup
						goto("/auth");
						return;
					}

					userId = authData.userId;
					name = authData.name;
					email = authData.email;
					loading = false;
				}
			});
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
				onsubmit={async (e) => {
					e.preventDefault();
					if (!userId || confirmationCode.length !== 6) return;

					submitting = true;
					error = null;
					pinError = false;

					try {
						// Use generated API client for consistency
						await api.auth.confirmSignUp({
							confirmRequest: {
								userId,
								code: confirmationCode,
							},
						});

						// session_id cookie is set by the server (httpOnly)
						// Now get access_token by calling /auth/refresh
						const token = await refreshAccessToken();

						if (!token) {
							// Failed to get access token - this could be a session issue
							console.error("Failed to refresh access token after confirmation");
							error = $_("auth.confirmation.errors.connectionError");
							return;
						}

						// Clear temporary auth data
						clearAuthData();

						// Redirect to home
						goto("/");
					} catch (err) {
						console.error("Error confirming code:", err);
						pinError = true;

						if (err instanceof ApiError) {
							// API error already translated by wrapper
							error = err.message;
						} else if (err instanceof NetworkError) {
							error = err.message;
						} else {
							error = $_("auth.confirmation.errors.connectionError");
						}
					} finally {
						submitting = false;
					}
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
								// Find the form element (it's the parent form)
								const form = document.querySelector("form") as HTMLFormElement;
								if (form) {
									// Trigger form submission
									form.requestSubmit();
								}
							}
						}}
						onChange={(code) => {
							confirmationCode = code;
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
