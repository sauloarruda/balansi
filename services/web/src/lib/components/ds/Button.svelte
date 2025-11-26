<script lang="ts">
	interface Props {
		type?: "button" | "submit" | "reset";
		disabled?: boolean;
		loading?: boolean;
		children?: import("svelte").Snippet;
		onclick?: (event: MouseEvent) => void;
	}

	let { type = "button", disabled = false, loading = false, children, onclick }: Props = $props();

	let buttonElement: HTMLButtonElement;
</script>

<button
	bind:this={buttonElement}
	{type}
	{disabled}
	onclick={onclick}
	class="w-full mt-8 py-3 px-4 rounded-lg flex items-center justify-center gap-2 bg-primary text-white font-semibold hover:bg-primary-600 disabled:opacity-60 disabled:cursor-not-allowed"
>
	{#if loading}
		<div
			class="animate-spin inline-block size-4 border-2 border-current border-t-transparent rounded-full"
			role="status"
			aria-label="loading"
		>
			<span class="sr-only">Loading...</span>
		</div>
	{/if}
	{#if children}
		{@render children()}
	{/if}
</button>
