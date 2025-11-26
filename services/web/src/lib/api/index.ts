// Export API client wrapper with i18n integration
export { ApiError, NetworkError, api, createApiConfig, getApiBaseUrl } from "./wrapper";

// Export types directly from generated client
export type {
    ConfirmRequest, ForgotPasswordRequest, ForgotPasswordResponse,
    ResetPasswordRequest, ResetPasswordResponse, SignupRequest,
    SignupResponse, TokenResponse
} from "./generated";
