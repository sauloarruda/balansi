<script lang="ts">
	interface Props {
		length?: number;
		value?: string;
		disabled?: boolean;
		onComplete?: (value: string) => void;
		onChange?: (value: string) => void;
		error?: boolean;
		errorMessage?: string;
		autoFocus?: boolean;
	}

	let {
		length = 6,
		value = $bindable(""),
		disabled = false,
		onComplete,
		onChange,
		error = false,
		errorMessage = "",
		autoFocus = true,
	}: Props = $props();

	// Array to hold input references - initialize with correct length
	let inputRefs: (HTMLInputElement | null)[] = $state(Array(length).fill(null));

	// Auto-focus first input on mount
	$effect(() => {
		if (autoFocus && !disabled && inputRefs[0]) {
			// Small delay to ensure the input is fully rendered and interactive
			const timeoutId = setTimeout(() => {
				inputRefs[0]?.focus();
			}, 100);

			return () => clearTimeout(timeoutId);
		}
	});

	// Sync internal state with bound value prop
	$effect(() => {
		if (value.length !== length && value.length > 0) {
			// Ensure value matches length requirement if provided
			// but don't truncate if empty to allow clear
		}

		// Update input values if they don't match the bound value string
		// This handles external updates to 'value'
		inputRefs.forEach((input, index) => {
			if (input) {
				const char = value[index] || "";
				if (input.value !== char) {
					input.value = char;
				}
			}
		});
	});

	function updateValue() {
		// Reconstruct value from inputs
		const newValue = inputRefs
			.map((input) => input?.value || "")
			.join("")
			.slice(0, length);

		value = newValue;
		onChange?.(newValue);

		if (newValue.length === length) {
			onComplete?.(newValue);
		}
	}

	async function handleInput(index: number, e: Event) {
		const target = e.target as HTMLInputElement;
		let inputValue = target.value;

		// Only allow digits
		if (!/^\d*$/.test(inputValue)) {
			target.value = "";
			return; // Do not update state
		}

		// Limit to single digit - take the last character if multiple entered
		if (inputValue.length > 1) {
			inputValue = inputValue.slice(-1);
			target.value = inputValue;
		}

		updateValue();

		// Move to next input if digit entered
		if (inputValue && inputValue.length === 1 && index < length - 1) {
			// Focus immediately, no need to wait for tick() as inputs already exist
			const nextInput = inputRefs[index + 1];
			if (nextInput) {
				nextInput.focus();
				nextInput.select();
			}
		}
	}

	async function handleKeyDown(index: number, e: KeyboardEvent) {
		const target = e.target as HTMLInputElement;

		// Handle backspace
		if (e.key === "Backspace") {
			if (target.value) {
				// If there's a value, clear it
				target.value = "";
				updateValue();
			} else if (index > 0) {
				// If no value, move to previous, clear it and focus
				e.preventDefault(); // Prevent default backspace behavior
				const prevInput = inputRefs[index - 1];
				if (prevInput) {
					prevInput.value = "";
					prevInput.focus();
					updateValue();
				}
			}
		}

		// Handle arrow keys
		if (e.key === "ArrowLeft" && index > 0) {
			e.preventDefault();
			inputRefs[index - 1]?.focus();
		}
		if (e.key === "ArrowRight" && index < length - 1) {
			e.preventDefault();
			inputRefs[index + 1]?.focus();
		}
	}
	function handlePaste(e: Event) {
		// Cast to ClipboardEvent since Svelte events are generic
		const clipboardEvent = e as unknown as {
			clipboardData: { getData: (format: string) => string } | null;
			preventDefault: () => void;
		};
		clipboardEvent.preventDefault();
		const pastedData = clipboardEvent.clipboardData?.getData("text/plain").trim() || "";

		// Validate if pasted content is numeric
		if (!/^\d+$/.test(pastedData)) return;

		// Distribute pasted content to inputs
		// Update bound value directly which will trigger effect to update inputs
		value = pastedData.slice(0, length);

		onChange?.(value);

		if (value.length === length) {
			onComplete?.(value);

			// Focus last input
			inputRefs[length - 1]?.focus();
		} else {
			// Focus next empty input
			inputRefs[value.length]?.focus();
		}
	}
</script>

<div class="pin-input-container">
	<div class="hs-pin-input flex gap-2 justify-center" role="group" aria-label="PIN Input">
		{#each Array(length) as _, i}
			{@const inputIndex = i}
			<input
				bind:this={inputRefs[inputIndex]}
				type="text"
				inputmode="numeric"
				pattern="[0-9]*"
				maxlength="1"
				class="hs-pin-input-input w-12 h-12 text-center text-lg font-semibold border rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500 disabled:opacity-50 disabled:cursor-not-allowed {error
					? 'border-red-500 focus:border-red-500 focus:ring-red-500'
					: 'border-gray-300'}"
				{disabled}
				oninput={(e) => handleInput(inputIndex, e)}
				onkeydown={(e) => handleKeyDown(inputIndex, e)}
				onpaste={handlePaste}
				aria-label="PIN digit {inputIndex + 1}"
				autocomplete="one-time-code"
			/>
		{/each}
	</div>
	{#if error && errorMessage}
		<p class="mt-2 text-sm text-red-600 text-center">{errorMessage}</p>
	{/if}
</div>

<style>
	.pin-input-container input {
		transition: all 0.2s ease-in-out;
	}
</style>
