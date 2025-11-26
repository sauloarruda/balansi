// Export API client wrapper with i18n integration
export { ApiError, NetworkError, api, getApiBaseUrl, createApiConfig } from "./wrapper";

// Export types directly from generated client
export type {
    ConfirmRequest, SignupRequest,
    SignupResponse, TokenResponse
} from "./generated";
