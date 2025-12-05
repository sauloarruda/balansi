<script lang="ts">
	import type { CreateMealRequest } from "$lib/api/journal";
	import { _ } from "$lib/i18n";

	interface Props {
		onSubmit: (meal: CreateMealRequest) => Promise<void>;
		loading?: boolean;
	}

	let { onSubmit, loading = false }: Props = $props();

	type MealType = "breakfast" | "lunch" | "snack" | "dinner";

	let mealType = $state<MealType>("lunch");
	let description = $state("");
	let date = $state(new Date().toISOString().split("T")[0]);

	const mealTypes: { value: MealType; icon: string; label: string }[] = [
		{ value: "breakfast", icon: "🌅", label: "journal.mealTypes.breakfast" },
		{ value: "lunch", icon: "☀️", label: "journal.mealTypes.lunch" },
		{ value: "snack", icon: "🍎", label: "journal.mealTypes.snack" },
		{ value: "dinner", icon: "🌙", label: "journal.mealTypes.dinner" },
	];

	async function handleSubmit(e: Event) {
		e.preventDefault();
		if (!description.trim() || loading) return;

		await onSubmit({
			date,
			meal_type: mealType,
			original_description: description.trim(),
		});

		// Clear form after successful submit
		description = "";
	}

	function selectMealType(type: MealType) {
		mealType = type;
	}
</script>

<form onsubmit={handleSubmit} class="bg-white rounded-2xl shadow-lg p-6 border border-amber-100">
	<!-- Date picker -->
	<div class="mb-5">
		<label for="meal-date" class="block text-sm font-medium text-stone-600 mb-2">
			{$_("journal.form.date")}
		</label>
		<input
			type="date"
			id="meal-date"
			bind:value={date}
			class="w-full px-4 py-3 rounded-xl border border-stone-200 focus:border-amber-400 focus:ring-2 focus:ring-amber-100 outline-none transition-all text-stone-700"
		/>
	</div>

	<!-- Meal type selector -->
	<div class="mb-5">
		<label class="block text-sm font-medium text-stone-600 mb-3">
			{$_("journal.form.mealType")}
		</label>
		<div class="grid grid-cols-4 gap-2">
			{#each mealTypes as type}
				<button
					type="button"
					onclick={() => selectMealType(type.value)}
					class="flex flex-col items-center p-3 rounded-xl transition-all duration-200 {mealType ===
					type.value
						? 'bg-gradient-to-br from-amber-400 to-orange-400 text-white shadow-md scale-105'
						: 'bg-stone-50 text-stone-600 hover:bg-amber-50 hover:scale-102'}"
				>
					<span class="text-2xl mb-1">{type.icon}</span>
					<span class="text-xs font-medium truncate w-full text-center">
						{$_(type.label)}
					</span>
				</button>
			{/each}
		</div>
	</div>

	<!-- Description textarea -->
	<div class="mb-5">
		<label for="meal-description" class="block text-sm font-medium text-stone-600 mb-2">
			{$_("journal.form.description")}
		</label>
		<textarea
			id="meal-description"
			bind:value={description}
			placeholder={$_("journal.form.descriptionPlaceholder")}
			rows="3"
			class="w-full px-4 py-3 rounded-xl border border-stone-200 focus:border-amber-400 focus:ring-2 focus:ring-amber-100 outline-none transition-all resize-none text-stone-700 placeholder:text-stone-400"
		></textarea>
		<p class="mt-2 text-xs text-stone-500">
			{$_("journal.form.descriptionHint")}
		</p>
	</div>

	<!-- Submit button -->
	<button
		type="submit"
		disabled={!description.trim() || loading}
		class="w-full py-4 px-6 rounded-xl font-semibold text-white transition-all duration-200 flex items-center justify-center gap-3
			{!description.trim() || loading
			? 'bg-stone-300 cursor-not-allowed'
			: 'bg-gradient-to-r from-amber-500 to-orange-500 hover:from-amber-600 hover:to-orange-600 shadow-lg hover:shadow-xl hover:-translate-y-0.5'}"
	>
		{#if loading}
			<div
				class="animate-spin size-5 border-2 border-white border-t-transparent rounded-full"
				role="status"
			></div>
			<span>{$_("journal.form.analyzing")}</span>
		{:else}
			<svg class="size-5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
				<path
					stroke-linecap="round"
					stroke-linejoin="round"
					d="M9.813 15.904L9 18.75l-.813-2.846a4.5 4.5 0 00-3.09-3.09L2.25 12l2.846-.813a4.5 4.5 0 003.09-3.09L9 5.25l.813 2.846a4.5 4.5 0 003.09 3.09L15.75 12l-2.846.813a4.5 4.5 0 00-3.09 3.09zM18.259 8.715L18 9.75l-.259-1.035a3.375 3.375 0 00-2.455-2.456L14.25 6l1.036-.259a3.375 3.375 0 002.455-2.456L18 2.25l.259 1.035a3.375 3.375 0 002.456 2.456L21.75 6l-1.035.259a3.375 3.375 0 00-2.456 2.456z"
				/>
			</svg>
			<span>{$_("journal.form.submit")}</span>
		{/if}
	</button>
</form>
