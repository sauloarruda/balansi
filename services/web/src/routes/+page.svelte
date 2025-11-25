<script lang="ts">
	import { enhance } from "$app/forms";
	import { goto } from "$app/navigation";
	import Button from "$lib/components/ds/Button.svelte";
	import Container from "$lib/components/ds/Container.svelte";
	import { _ } from "$lib/i18n";
	import type { PageData } from "./$types";

	let { data }: { data: PageData } = $props();

	let loading = $state(true);
	let loggingOut = $state(false);

	// Redirect if not authenticated
	$effect(() => {
		if (!data.authenticated) {
			goto("/auth");
		} else {
			loading = false;
		}
	});
</script>

<Container {loading}>
	{#snippet children()}
		<div class="flex flex-col items-center">
			<h2 class="text-xl font-semibold mb-6 text-center">
				{$_("home.welcome")}
			</h2>
			<p class="text-center mb-6">
				{$_("home.ready")}
			</p>
			<form
				method="POST"
				action="?/logout"
				use:enhance={({ formData, cancel }) => {
					loggingOut = true;
					return async ({ result, update }) => {
						loggingOut = false;
						if (result.type === "redirect") {
							// Server redirected - let it handle the redirect
							await update();
							return;
						}
					};
				}}
			>
				<Button type="submit" loading={loggingOut} disabled={loggingOut}>
					{$_("auth.logout")}
				</Button>
			</form>
		</div>
	{/snippet}
</Container>
