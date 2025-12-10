/**
 * Custom API error with translated message
 */
export class ApiError extends Error {
	constructor(
		message: string,
		public status: number,
		public code?: string,
		public originalMessage?: string
	) {
		super(message);
		this.name = "ApiError";
	}
}

/**
 * Network/connection error
 */
export class NetworkError extends Error {
	constructor(message: string) {
		super(message);
		this.name = "NetworkError";
	}
}

/**
 * Get API base URL from environment
 */
export function getApiBaseUrl(): string {
	return import.meta.env.VITE_API_URL ?? "http://localhost:3000";
}
