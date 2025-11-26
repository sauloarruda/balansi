<script lang="ts">
	import { goto } from "$app/navigation";
	import { checkAuth, logout as clientLogout } from "$lib/auth/clientAuth";
	import Button from "$lib/components/ds/Button.svelte";
	import Container from "$lib/components/ds/Container.svelte";
	import { _ } from "$lib/i18n";

	let loading = $state(true);
	let authenticated = $state(checkAuth());
	let loggingOut = $state(false);

	// Check authentication on mount
	$effect(() => {
		if (!authenticated) {
			goto("/auth");
		} else {
			loading = false;
		}
	});

	async function handleLogout() {
		loggingOut = true;
		try {
			await clientLogout();
			goto("/auth");
		} catch (error) {
			console.error("Logout error:", error);
		} finally {
			loggingOut = false;
		}
	}
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
			<Button type="button" loading={loggingOut} disabled={loggingOut} onclick={handleLogout}>
				{$_("auth.logout")}
			</Button>
		</div>
	{/snippet}
</Container>
