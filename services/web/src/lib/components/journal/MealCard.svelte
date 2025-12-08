<script lang="ts">
	import type { MealEntry } from "$lib/api/journal";
	import { _ } from "$lib/i18n";

	interface Props {
		meal: MealEntry;
		onConfirm?: (id: number) => Promise<void>;
		confirming?: boolean;
	}

	let { meal, onConfirm, confirming = false }: Props = $props();

	const mealTypeConfig = {
		breakfast: { icon: "🌅", gradient: "from-amber-400 to-yellow-300" },
		lunch: { icon: "☀️", gradient: "from-orange-400 to-amber-300" },
		snack: { icon: "🍎", gradient: "from-rose-400 to-pink-300" },
		dinner: { icon: "🌙", gradient: "from-indigo-400 to-purple-300" },
	};

	const statusConfig = {
		pending: { color: "bg-stone-100 text-stone-600", label: "journal.status.pending" },
		processing: { color: "bg-blue-100 text-blue-700", label: "journal.status.processing" },
		in_review: { color: "bg-amber-100 text-amber-700", label: "journal.status.inReview" },
		confirmed: { color: "bg-emerald-100 text-emerald-700", label: "journal.status.confirmed" },
	};

	const config = $derived(mealTypeConfig[meal.meal_type]);
	const status = $derived(statusConfig[meal.status]);

	function formatNumber(value: number | null): string {
		if (value === null) return "-";
		return Math.round(value).toString();
	}

	async function handleConfirm() {
		if (onConfirm && !confirming) {
			await onConfirm(meal.id);
		}
	}
</script>

<div
	class="bg-white rounded-2xl shadow-md border border-stone-100 overflow-hidden transition-all duration-300 hover:shadow-lg"
>
	<!-- Header with meal type -->
	<div class="bg-gradient-to-r {config.gradient} px-5 py-3 flex items-center justify-between">
		<div class="flex items-center gap-3">
			<span class="text-2xl">{config.icon}</span>
			<div>
				<h3 class="font-semibold text-white text-shadow">
					{$_(`journal.mealTypes.${meal.meal_type}`)}
				</h3>
				<p class="text-xs text-white/80">
					{new Date(meal.date).toLocaleDateString()}
				</p>
			</div>
		</div>
		<span class="px-3 py-1 rounded-full text-xs font-medium {status.color}">
			{$_(status.label)}
		</span>
	</div>

	<!-- Content -->
	<div class="p-5">
		<!-- Description -->
		<p class="text-stone-700 mb-4 line-clamp-2">
			{meal.original_description}
		</p>

		<!-- Macros grid -->
		{#if meal.status !== "pending" && meal.status !== "processing"}
			<div class="grid grid-cols-4 gap-3 mb-4">
				<div class="text-center p-3 bg-red-50 rounded-xl">
					<div class="text-lg font-bold text-red-600">{formatNumber(meal.protein_g)}</div>
					<div class="text-xs text-red-500 font-medium">{$_("journal.macros.protein")}</div>
				</div>
				<div class="text-center p-3 bg-amber-50 rounded-xl">
					<div class="text-lg font-bold text-amber-600">{formatNumber(meal.carbs_g)}</div>
					<div class="text-xs text-amber-500 font-medium">{$_("journal.macros.carbs")}</div>
				</div>
				<div class="text-center p-3 bg-blue-50 rounded-xl">
					<div class="text-lg font-bold text-blue-600">{formatNumber(meal.fat_g)}</div>
					<div class="text-xs text-blue-500 font-medium">{$_("journal.macros.fat")}</div>
				</div>
				<div class="text-center p-3 bg-emerald-50 rounded-xl">
					<div class="text-lg font-bold text-emerald-600">{formatNumber(meal.calories_kcal)}</div>
					<div class="text-xs text-emerald-500 font-medium">{$_("journal.macros.calories")}</div>
				</div>
			</div>

			<!-- AI Comment -->
			{#if meal.ai_comment}
				<div class="flex gap-3 p-3 bg-gradient-to-r from-violet-50 to-fuchsia-50 rounded-xl mb-4">
					<span class="text-xl">🤖</span>
					<p class="text-sm text-violet-700 italic">{meal.ai_comment}</p>
				</div>
			{/if}
		{:else}
			<!-- Loading state for pending/processing -->
			<div class="flex items-center justify-center gap-3 py-6 text-stone-500">
				<div
					class="animate-spin size-5 border-2 border-stone-300 border-t-stone-600 rounded-full"
				></div>
				<span class="text-sm">{$_("journal.analyzing")}</span>
			</div>
		{/if}

		<!-- Confirm button -->
		{#if meal.status === "in_review" && onConfirm}
			<button
				onclick={handleConfirm}
				disabled={confirming}
				class="w-full py-3 px-4 rounded-xl font-medium text-white transition-all duration-200 flex items-center justify-center gap-2
					{confirming
					? 'bg-stone-300 cursor-not-allowed'
					: 'bg-gradient-to-r from-emerald-500 to-teal-500 hover:from-emerald-600 hover:to-teal-600 shadow-md hover:shadow-lg'}"
			>
				{#if confirming}
					<div
						class="animate-spin size-4 border-2 border-white border-t-transparent rounded-full"
					></div>
				{:else}
					<svg
						class="size-5"
						fill="none"
						viewBox="0 0 24 24"
						stroke="currentColor"
						stroke-width="2"
					>
						<path stroke-linecap="round" stroke-linejoin="round" d="M5 13l4 4L19 7" />
					</svg>
				{/if}
				<span>{$_("journal.confirmMeal")}</span>
			</button>
		{/if}
	</div>
</div>

<style>
	.text-shadow {
		text-shadow: 0 1px 2px rgba(0, 0, 0, 0.1);
	}
</style>
