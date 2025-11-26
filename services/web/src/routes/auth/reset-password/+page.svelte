<script lang="ts">
	import { browser } from "$app/environment";
	import { goto } from "$app/navigation";
	import type { ResetPasswordRequest } from "$lib/api";
	import { api, ApiError, NetworkError } from "$lib/api";
	import { checkAuth } from "$lib/auth/clientAuth";
	import { passwordRecoveryData } from "$lib/auth/passwordRecoveryStorage";
	import Button from "$lib/components/ds/Button.svelte";
	import Container from "$lib/components/ds/Container.svelte";
	import Input from "$lib/components/ds/Input.svelte";
	import PinInput from "$lib/components/ds/PinInput.svelte";
	import { _ } from "$lib/i18n";
	import { getPasswordRequirements, isValidPassword } from "$lib/utils/validation";

	let loading = $state(true);
	let email = $state("");
	let destination = $state("");
	let code = $state("");
	let newPassword = $state("");
	let confirmPassword = $state("");
	let submitting = $state(false);
	let error = $state<string | null>(null);
	let pinError = $state(false);
	let success = $state(false);

	// Password requirements
	let requirements = $derived(getPasswordRequirements(newPassword));

	// Validation states
	let passwordsMatch = $derived(
		newPassword.length > 0 && confirmPassword.length > 0 && newPassword === confirmPassword
	);
	let passwordValid = $derived(isValidPassword(newPassword));
	let isFormValid = $derived(code.length === 6 && passwordValid && passwordsMatch);

	// Check authentication and load recovery data
	$effect(() => {
		const isAuth = checkAuth();
		if (isAuth) {
			// Already authenticated, redirect to home
			goto("/");
			return;
		}

		if (!browser) {
			loading = false;
			return;
		}

		// Get recovery data from localStorage
		const recovery = passwordRecoveryData.get();
		if (!recovery) {
			// Missing recovery data, redirect to forgot-password
			goto("/auth/forgot-password");
			return;
		}

		email = recovery.email;
		destination = recovery.destination;
		loading = false;
	});

	// Focus PIN input when page loads
	$effect(() => {
		if (!loading && browser && !submitting) {
			// Small delay to ensure PinInput is rendered
			window.setTimeout(() => {
				const firstInput = document.querySelector(
					'input[aria-label="PIN digit 1"]'
				) as HTMLInputElement;
				if (firstInput && !firstInput.disabled) {
					firstInput.focus();
				}
			}, 100);
		}
	});

	async function handleSubmit(e: SubmitEvent) {
		e.preventDefault();
		if (!isFormValid) return;

		submitting = true;
		error = null;
		pinError = false;

		try {
			const request: ResetPasswordRequest = {
				email,
				code,
				newPassword,
			};
			await api.auth.resetPassword({ resetPasswordRequest: request });

			// Clear recovery data
			passwordRecoveryData.clear();

			// Show success message
			success = true;

			// Redirect to login after a short delay
			setTimeout(() => {
				goto("/auth");
			}, 2000);
		} catch (err) {
			console.error("Error resetting password:", err);
			pinError = true;

			if (err instanceof ApiError) {
				// API error already translated
				error = err.message;
			} else if (err instanceof NetworkError) {
				// Network error
				error = err.message;
			} else {
				// Unknown error
				error = $_("auth.resetPassword.errors.connectionError");
			}
		} finally {
			submitting = false;
		}
	}

	function handleResendCode() {
		// Redirect back to forgot-password to resend code
		goto("/auth/forgot-password");
	}
</script>

<Container {loading}>
	{#snippet children()}
		{#if !loading}
			{#if success}
				<div class="text-center">
					<div class="mb-6">
						<svg
							class="mx-auto h-16 w-16 text-green-600 dark:text-green-400"
							fill="none"
							stroke="currentColor"
							viewBox="0 0 24 24"
						>
							<path
								stroke-linecap="round"
								stroke-linejoin="round"
								stroke-width="2"
								d="M5 13l4 4L19 7"
							/>
						</svg>
					</div>
					<h2 class="text-xl font-semibold mb-4">
						{$_("auth.resetPassword.success")}
					</h2>
					<p class="text-gray-600 dark:text-gray-400">{$_("common.loading")}</p>
				</div>
			{:else}
				<h2 class="text-xl font-semibold mb-6 text-center">
					{$_("auth.resetPassword.title")}
				</h2>

				<p class="text-center mb-6 text-gray-600 dark:text-gray-400">
					{$_("auth.resetPassword.description", { values: { destination } })}
				</p>

				{#if error && !pinError}
					<div class="error-message mb-4">{error}</div>
				{/if}

				<form onsubmit={handleSubmit} class="flex flex-col gap-6 my-8">
					<!-- PIN Input for Code -->
					<div class="flex flex-col gap-2">
						<label for="verification-code" class="text-sm font-medium text-gray-700 text-center">
							{$_("auth.resetPassword.code.label")}
						</label>
						<PinInput
							length={6}
							bind:value={code}
							disabled={submitting}
							error={pinError}
							errorMessage={error || ""}
							onChange={(newCode) => {
								code = newCode;
								// Clear error when user starts typing
								if (error) {
									error = null;
									pinError = false;
								}
							}}
						/>
					</div>

					<!-- New Password -->
					<div class="relative">
						<Input
							type="password"
							id="newPassword"
							name="newPassword"
							label={$_("auth.resetPassword.fields.newPassword.label")}
							placeholder={$_("auth.resetPassword.fields.newPassword.placeholder")}
							required
							minlength={8}
							bind:value={newPassword}
							disabled={submitting}
						/>
					</div>

					<!-- Confirm Password -->
					<div class="relative">
						<Input
							type="password"
							id="confirmPassword"
							name="confirmPassword"
							label={$_("auth.resetPassword.fields.confirmPassword.label")}
							placeholder={$_("auth.resetPassword.fields.confirmPassword.placeholder")}
							required
							minlength={8}
							bind:value={confirmPassword}
							disabled={submitting}
						/>
						{#if confirmPassword.length > 0 && !passwordsMatch}
							<p class="mt-1 text-sm text-red-600 dark:text-red-400">
								{$_("auth.resetPassword.errors.passwordMismatch")}
							</p>
						{/if}
					</div>

					<!-- Password Requirements -->
					{#if newPassword.length > 0}
						<div class="bg-gray-50 dark:bg-gray-800 p-4 rounded-lg">
							<p class="text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
								{$_("auth.resetPassword.requirements.title")}
							</p>
							<ul class="space-y-1">
								<li
									class="text-sm flex items-center gap-2"
									class:text-green-600={requirements.minLength}
									class:text-gray-600={!requirements.minLength}
								>
									<span class="text-lg">{requirements.minLength ? "✓" : "○"}</span>
									{$_("auth.resetPassword.requirements.minLength")}
								</li>
								<li
									class="text-sm flex items-center gap-2"
									class:text-green-600={requirements.hasUppercase}
									class:text-gray-600={!requirements.hasUppercase}
								>
									<span class="text-lg">{requirements.hasUppercase ? "✓" : "○"}</span>
									{$_("auth.resetPassword.requirements.uppercase")}
								</li>
								<li
									class="text-sm flex items-center gap-2"
									class:text-green-600={requirements.hasLowercase}
									class:text-gray-600={!requirements.hasLowercase}
								>
									<span class="text-lg">{requirements.hasLowercase ? "✓" : "○"}</span>
									{$_("auth.resetPassword.requirements.lowercase")}
								</li>
								<li
									class="text-sm flex items-center gap-2"
									class:text-green-600={requirements.hasNumber}
									class:text-gray-600={!requirements.hasNumber}
								>
									<span class="text-lg">{requirements.hasNumber ? "✓" : "○"}</span>
									{$_("auth.resetPassword.requirements.number")}
								</li>
								<li
									class="text-sm flex items-center gap-2"
									class:text-green-600={requirements.hasSpecial}
									class:text-gray-600={!requirements.hasSpecial}
								>
									<span class="text-lg">{requirements.hasSpecial ? "✓" : "○"}</span>
									{$_("auth.resetPassword.requirements.special")}
								</li>
							</ul>
						</div>
					{/if}

					<Button type="submit" loading={submitting} disabled={submitting || !isFormValid}>
						{$_("auth.resetPassword.submit")}
					</Button>
				</form>

				<div class="text-center">
					<button
						type="button"
						class="text-sm text-blue-600 hover:text-blue-800 dark:text-blue-400 dark:hover:text-blue-300"
						onclick={handleResendCode}
						disabled={submitting}
					>
						{$_("auth.resetPassword.resendCode")}
					</button>
				</div>
			{/if}
		{/if}
	{/snippet}
</Container>

