<script lang="ts">
	import { browser } from "$app/environment";

	interface Props {
		date: string;
		onDateChange: (date: string) => void;
	}

	let { date, onDateChange }: Props = $props();

	// Format date for display
	let formattedDate = $state("");

	// Update formatted date when date prop changes
	$effect(() => {
		if (!browser) {
			formattedDate = date;
			return;
		}
		try {
			const d = new Date(date + "T00:00:00");
			if (isNaN(d.getTime())) {
				formattedDate = date;
				return;
			}
			const locale = navigator.language || "en-US";
			formattedDate = d.toLocaleDateString(locale, {
				month: "short",
				day: "numeric",
				year: "numeric",
			});
		} catch {
			formattedDate = date;
		}
	});

	// Check if the selected date is today
	const isToday = $derived(() => {
		if (!browser) return false;
		const today = new Date().toISOString().split("T")[0];
		return date === today;
	});

	// Get max date (today) for the date input
	const maxDate = $derived(() => {
		if (!browser) return "";
		return new Date().toISOString().split("T")[0];
	});

	function goToPreviousDay() {
		const currentDate = new Date(date + "T00:00:00");
		currentDate.setDate(currentDate.getDate() - 1);
		const newDate = currentDate.toISOString().split("T")[0];
		onDateChange(newDate);
	}

	function goToNextDay() {
		if (isToday()) return;
		const currentDate = new Date(date + "T00:00:00");
		currentDate.setDate(currentDate.getDate() + 1);
		const newDate = currentDate.toISOString().split("T")[0];
		onDateChange(newDate);
	}

	function handleDateInputChange(e: Event) {
		const target = e.target as HTMLInputElement;
		if (target.value) {
			const selectedDate = target.value;
			const today = new Date().toISOString().split("T")[0];

			// Validate that selected date is not in the future
			if (selectedDate > today) {
				// Reset to today if future date is selected
				target.value = today;
				onDateChange(today);
			} else {
				onDateChange(selectedDate);
			}
		}
	}

	let dateInput: HTMLInputElement | null = $state(null);

	function handleButtonClick(e: MouseEvent) {
		e.stopPropagation();

		if (!dateInput) return;

		// Try to use showPicker API synchronously within the user gesture
		if (typeof dateInput.showPicker === "function") {
			try {
				dateInput.showPicker();
			} catch (err) {
				// If showPicker fails, fallback to clicking the input
				dateInput.click();
			}
		} else {
			// For browsers without showPicker, click the input directly
			dateInput.click();
		}
	}

</script>

<div class="flex items-center gap-3">
	<!-- Previous day button -->
	<button
		type="button"
		onclick={goToPreviousDay}
		class="p-2 rounded-lg hover:bg-stone-100 transition-colors text-stone-600 hover:text-stone-800"
		aria-label="Previous day"
	>
		<svg class="size-5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
			<path stroke-linecap="round" stroke-linejoin="round" d="M15.75 19.5L8.25 12l7.5-7.5" />
		</svg>
	</button>

	<!-- Date display and calendar input -->
	<div class="relative">
		<input
			bind:this={dateInput}
			type="date"
			value={date}
			max={maxDate}
			onchange={handleDateInputChange}
			class="sr-only"
			aria-label="Select date"
			id="date-picker-input"
		/>
		<button
			type="button"
			onclick={handleButtonClick}
			class="inline-flex items-center gap-2 px-4 py-2 rounded-lg font-medium text-stone-700 border border-stone-200 hover:bg-stone-100 focus:bg-stone-100 focus:border-amber-400 focus:ring-2 focus:ring-amber-100 outline-none bg-white transition-colors cursor-pointer"
			aria-label="Select date"
			aria-describedby="date-picker-input"
		>
			<svg
				class="size-4 text-stone-500"
				fill="none"
				viewBox="0 0 24 24"
				stroke="currentColor"
				stroke-width="2"
			>
				<path
					stroke-linecap="round"
					stroke-linejoin="round"
					d="M6.75 3v2.25M17.25 3v2.25M3 18.75V7.5a2.25 2.25 0 012.25-2.25h13.5A2.25 2.25 0 0121 7.5v11.25m-18 0A2.25 2.25 0 005.25 21h13.5A2.25 2.25 0 0021 18.75m-18 0v-7.5A2.25 2.25 0 015.25 9h13.5A2.25 2.25 0 0121 11.25v7.5"
				/>
			</svg>
			<span>{formattedDate}</span>
		</button>
	</div>

	<!-- Next day button -->
	<button
		type="button"
		onclick={goToNextDay}
		disabled={isToday()}
		class="p-2 rounded-lg transition-colors {isToday()
			? 'text-stone-300 cursor-not-allowed'
			: 'text-stone-600 hover:bg-stone-100 hover:text-stone-800'}"
		aria-label="Next day"
	>
		<svg class="size-5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
			<path stroke-linecap="round" stroke-linejoin="round" d="M8.25 4.5l7.5 7.5-7.5 7.5" />
		</svg>
	</button>
</div>
