<script lang="ts">
	import { browser } from "$app/environment";
	import { goto } from "$app/navigation";
	import { logout as clientLogout } from "$lib/auth/clientAuth";
	import { hasSession } from "$lib/auth/session";
	import Button from "$lib/components/ds/Button.svelte";
	import Container from "$lib/components/ds/Container.svelte";
	import { _ } from "$lib/i18n";

	let loading = $state(true);
	let authenticated = $state(false);
	let loggingOut = $state(false);

	// Check authentication on mount (async to allow token refresh)
	$effect(() => {
		if (!browser) return;

		hasSession().then((isAuth) => {
			if (!isAuth) {
				goto("/auth");
			} else {
				authenticated = true;
				loading = false;
			}
		});
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

			<!-- Journal Link -->
			<a
				href="/journal"
				class="w-full mb-4 py-4 px-6 rounded-xl font-semibold text-white bg-gradient-to-r from-amber-500 to-orange-500 hover:from-amber-600 hover:to-orange-600 shadow-lg hover:shadow-xl transition-all duration-200 flex items-center justify-center gap-3"
			>
				<span class="text-xl">🍽️</span>
				<span>{$_("journal.title")}</span>
			</a>

			<Button type="button" loading={loggingOut} disabled={loggingOut} onclick={handleLogout}>
				{$_("auth.logout")}
			</Button>
		</div>
	{/snippet}
</Container>
