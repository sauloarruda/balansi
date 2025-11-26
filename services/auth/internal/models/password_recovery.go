package models

// ForgotPasswordRequest represents the request to initiate password recovery.
type ForgotPasswordRequest struct {
	Email string `json:"email"`
}

// ForgotPasswordResponse represents the response after initiating password recovery.
type ForgotPasswordResponse struct {
	Success        bool   `json:"success"`
	Destination    string `json:"destination"`
	DeliveryMedium string `json:"deliveryMedium"`
}

// ResetPasswordRequest represents the request to reset password with confirmation code.
type ResetPasswordRequest struct {
	Email       string `json:"email"`
	Code        string `json:"code"`
	NewPassword string `json:"newPassword"`
}

// ResetPasswordResponse represents the response after password reset.
type ResetPasswordResponse struct {
	Success bool `json:"success"`
}
