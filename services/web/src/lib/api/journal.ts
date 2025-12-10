import { getAccessToken } from "$lib/auth/token";
import { _ } from "$lib/i18n";
import { get } from "svelte/store";
import { ApiError, getApiBaseUrl, NetworkError } from "./wrapper";

/**
 * Journal API base URL - uses separate service
 */
function getJournalApiUrl(): string {
	// Use VITE_JOURNAL_API_URL if set, otherwise derive from API_URL
	const journalUrl = import.meta.env.VITE_JOURNAL_API_URL;
	if (journalUrl) return journalUrl;

	// Fallback: replace auth port with journal port for local dev
	const baseUrl = getApiBaseUrl();
	return baseUrl.replace(':3000', ':4000');
}

/**
 * Meal entry from the API
 */
export interface MealEntry {
	id: number;
	patient_id: number;
	date: string;
	meal_type: 'breakfast' | 'lunch' | 'snack' | 'dinner';
	original_description: string;
	protein_g: number | null;
	carbs_g: number | null;
	fat_g: number | null;
	calories_kcal: number | null;
	weight_g: number | null;
	ai_comment: string | null;
	status: 'pending' | 'processing' | 'in_review' | 'confirmed';
	has_manual_override: boolean;
	created_at: string;
	updated_at: string;
}

/**
 * Request to create a meal
 */
export interface CreateMealRequest {
	date: string;
	meal_type: 'breakfast' | 'lunch' | 'snack' | 'dinner';
	original_description: string;
}

/**
 * Make an authenticated request to the Journal API
 */
async function journalFetch<T>(
	endpoint: string,
	options: RequestInit = {}
): Promise<T> {
	const baseUrl = getJournalApiUrl();
	const url = `${baseUrl}/journal${endpoint}`;

	const headers = new Headers(options.headers);
	headers.set('Content-Type', 'application/json');

	// Add auth token if available
	const token = await getAccessToken();
	if (token) {
		headers.set('Authorization', `Bearer ${token}`);
	}

	try {
		const response = await fetch(url, {
			...options,
			headers,
		});

		if (!response.ok) {
			const status = response.status;
			try {
				const data = await response.json();
				throw new ApiError(
					data.error || get(_)("errors.serverError"),
					status,
					data.code
				);
			} catch (e) {
				if (e instanceof ApiError) throw e;
				throw new ApiError(get(_)("errors.serverError"), status);
			}
		}

		return await response.json();
	} catch (error) {
		if (error instanceof ApiError) throw error;
		throw new NetworkError(get(_)("errors.serverError"));
	}
}

/**
 * Journal API client
 */
export const journalApi = {
	/**
	 * Create a new meal entry
	 */
	async createMeal(meal: CreateMealRequest): Promise<MealEntry> {
		const response = await journalFetch<{ data: MealEntry }>('/meals', {
			method: 'POST',
			body: JSON.stringify(meal),
		});
		return response.data;
	},

	/**
	 * List meals, optionally filtered by date
	 */
	async listMeals(date?: string): Promise<MealEntry[]> {
		const params = date ? `?date=${date}` : '';
		const response = await journalFetch<{ data: MealEntry[] }>(`/meals${params}`);
		return response.data;
	},

	/**
	 * Get a single meal by ID
	 */
	async getMeal(id: number): Promise<MealEntry> {
		const response = await journalFetch<{ data: MealEntry }>(`/meals/${id}`);
		return response.data;
	},

	/**
	 * Confirm a meal (accept AI estimation)
	 */
	async confirmMeal(id: number): Promise<MealEntry> {
		const response = await journalFetch<{ data: MealEntry }>(`/meals/${id}/confirm`, {
			method: 'POST',
		});
		return response.data;
	},
};
