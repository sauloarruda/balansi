<script lang="ts">
	import type { CreateMealRequest } from "$lib/api/journal";
	import { journalApi, type MealEntry } from "$lib/api/journal";
	import MealCard from "$lib/components/journal/MealCard.svelte";
	import MealForm from "$lib/components/journal/MealForm.svelte";
	import { _ } from "$lib/i18n";

	let loading = $state(true);
	let submitting = $state(false);
	let confirmingId = $state<number | null>(null);
	let meals = $state<MealEntry[]>([]);
	let error = $state<string | null>(null);
	let selectedDate = $state(new Date().toISOString().split("T")[0]);

	// Check authentication and load meals on mount
	// $effect(() => {
	// 	if (!browser) return;

	// 	hasSession().then(async (isAuth) => {
	// 		if (!isAuth) {
	// 			goto("/auth");
	// 			return;
	// 		}
	// 		await loadMeals();
	// 	});
	// });

	async function loadMeals() {
		loading = true;
		error = null;
		try {
			meals = await journalApi.listMeals(selectedDate);
		} catch (e) {
			console.error("Failed to load meals:", e);
			error = e instanceof Error ? e.message : "Failed to load meals";
		} finally {
			loading = false;
		}
	}

	async function handleSubmit(meal: CreateMealRequest) {
		submitting = true;
		error = null;
		try {
			const newMeal = await journalApi.createMeal(meal);
			// Add to list if same date, or refresh
			if (meal.date === selectedDate) {
				meals = [newMeal, ...meals];
			}
		} catch (e) {
			console.error("Failed to create meal:", e);
			error = e instanceof Error ? e.message : "Failed to create meal";
		} finally {
			submitting = false;
		}
	}

	async function handleConfirm(id: number) {
		confirmingId = id;
		try {
			const updatedMeal = await journalApi.confirmMeal(id);
			meals = meals.map((m) => (m.id === id ? updatedMeal : m));
		} catch (e) {
			console.error("Failed to confirm meal:", e);
			error = e instanceof Error ? e.message : "Failed to confirm meal";
		} finally {
			confirmingId = null;
		}
	}

	function handleDateChange(e: Event) {
		const target = e.target as HTMLInputElement;
		selectedDate = target.value;
		loadMeals();
	}

	// Calculate daily totals
	const dailyTotals = $derived(() => {
		const confirmed = meals.filter((m) => m.status === "confirmed" || m.status === "in_review");
		return {
			calories: confirmed.reduce((sum, m) => sum + (m.calories_kcal || 0), 0),
			protein: confirmed.reduce((sum, m) => sum + (m.protein_g || 0), 0),
			carbs: confirmed.reduce((sum, m) => sum + (m.carbs_g || 0), 0),
			fat: confirmed.reduce((sum, m) => sum + (m.fat_g || 0), 0),
		};
	});
</script>

<svelte:head>
	<title>{$_("journal.title")} | Balansi</title>
</svelte:head>

<div class="min-h-screen bg-gradient-to-br from-amber-50 via-orange-50 to-rose-50">
	<!-- Header -->
	<header class="bg-white/80 backdrop-blur-sm border-b border-amber-100 sticky top-0 z-10">
		<div class="max-w-2xl mx-auto px-4 py-4">
			<div class="flex items-center justify-between">
				<div class="flex items-center gap-3">
					<span class="text-3xl">🍽️</span>
					<div>
						<h1 class="text-xl font-bold text-stone-800">{$_("journal.title")}</h1>
						<p class="text-sm text-stone-500">{$_("journal.subtitle")}</p>
					</div>
				</div>
				<a
					href="/"
					class="p-2 rounded-xl hover:bg-stone-100 transition-colors text-stone-500 hover:text-stone-700"
				>
					<svg
						class="size-6"
						fill="none"
						viewBox="0 0 24 24"
						stroke="currentColor"
						stroke-width="2"
					>
						<path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" />
					</svg>
				</a>
			</div>
		</div>
	</header>

	<main class="max-w-2xl mx-auto px-4 py-6 space-y-6">
		<!-- Error message -->
		{#if error}
			<div class="bg-red-50 border border-red-200 rounded-xl p-4 flex items-start gap-3">
				<svg
					class="size-5 text-red-500 flex-shrink-0 mt-0.5"
					fill="none"
					viewBox="0 0 24 24"
					stroke="currentColor"
					stroke-width="2"
				>
					<path
						stroke-linecap="round"
						stroke-linejoin="round"
						d="M12 9v3.75m9-.75a9 9 0 11-18 0 9 9 0 0118 0zm-9 3.75h.008v.008H12v-.008z"
					/>
				</svg>
				<p class="text-red-700 text-sm">{error}</p>
			</div>
		{/if}

		<!-- Meal Form -->
		<MealForm onSubmit={handleSubmit} loading={submitting} />

		<!-- Daily Summary -->
		{#if meals.length > 0}
			<div class="bg-white rounded-2xl shadow-lg p-5 border border-amber-100">
				<div class="flex items-center justify-between mb-4">
					<h2 class="font-semibold text-stone-700 flex items-center gap-2">
						<span>📊</span>
						{$_("journal.dailySummary")}
					</h2>
					<input
						type="date"
						value={selectedDate}
						onchange={handleDateChange}
						class="text-sm px-3 py-1.5 rounded-lg border border-stone-200 focus:border-amber-400 focus:ring-2 focus:ring-amber-100 outline-none"
					/>
				</div>
				<div class="grid grid-cols-4 gap-3">
					<div class="text-center">
						<div class="text-2xl font-bold text-emerald-600">
							{Math.round(dailyTotals().calories)}
						</div>
						<div class="text-xs text-stone-500">{$_("journal.macros.calories")}</div>
					</div>
					<div class="text-center">
						<div class="text-2xl font-bold text-red-500">{Math.round(dailyTotals().protein)}g</div>
						<div class="text-xs text-stone-500">{$_("journal.macros.protein")}</div>
					</div>
					<div class="text-center">
						<div class="text-2xl font-bold text-amber-500">{Math.round(dailyTotals().carbs)}g</div>
						<div class="text-xs text-stone-500">{$_("journal.macros.carbs")}</div>
					</div>
					<div class="text-center">
						<div class="text-2xl font-bold text-blue-500">{Math.round(dailyTotals().fat)}g</div>
						<div class="text-xs text-stone-500">{$_("journal.macros.fat")}</div>
					</div>
				</div>
			</div>
		{/if}

		<!-- Meals List -->
		<section>
			<h2 class="font-semibold text-stone-700 mb-4 flex items-center gap-2">
				<span>📝</span>
				{$_("journal.todaysMeals")}
			</h2>

			{#if loading}
				<div class="flex items-center justify-center py-12">
					<div
						class="animate-spin size-8 border-3 border-amber-200 border-t-amber-500 rounded-full"
					></div>
				</div>
			{:else if meals.length === 0}
				<div class="text-center py-12 bg-white rounded-2xl border border-dashed border-stone-200">
					<span class="text-5xl mb-4 block">🍴</span>
					<p class="text-stone-500">{$_("journal.noMeals")}</p>
					<p class="text-stone-400 text-sm mt-1">{$_("journal.noMealsHint")}</p>
				</div>
			{:else}
				<div class="space-y-4">
					{#each meals as meal (meal.id)}
						<div class="animate-fade-in">
							<MealCard {meal} onConfirm={handleConfirm} confirming={confirmingId === meal.id} />
						</div>
					{/each}
				</div>
			{/if}
		</section>
	</main>
</div>

<style>
	@keyframes fade-in {
		from {
			opacity: 0;
			transform: translateY(10px);
		}
		to {
			opacity: 1;
			transform: translateY(0);
		}
	}

	.animate-fade-in {
		animation: fade-in 0.3s ease-out;
	}
</style>
