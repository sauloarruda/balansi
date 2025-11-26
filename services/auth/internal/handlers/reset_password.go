package handlers

import (
	"context"
	"encoding/json"
	"errors"
	"services/auth/internal/http"
	"services/auth/internal/logger"
	"services/auth/internal/models"
	"services/auth/internal/services"

	"github.com/aws/aws-lambda-go/events"
)

type ResetPasswordHandler struct {
	passwordRecoveryService PasswordRecoveryServiceInterface
}

func NewResetPasswordHandler(passwordRecoveryService *services.PasswordRecoveryService) *ResetPasswordHandler {
	return NewResetPasswordHandlerWithInterface(passwordRecoveryService)
}

// NewResetPasswordHandlerWithInterface creates a handler with an interface-based service
// This allows for easier testing with mocks.
func NewResetPasswordHandlerWithInterface(passwordRecoveryService PasswordRecoveryServiceInterface) *ResetPasswordHandler {
	return &ResetPasswordHandler{
		passwordRecoveryService: passwordRecoveryService,
	}
}

func (h *ResetPasswordHandler) Handle(ctx context.Context, req events.APIGatewayV2HTTPRequest) (events.APIGatewayV2HTTPResponse, error) {
	// Parse request body
	var resetPasswordReq models.ResetPasswordRequest
	if err := json.Unmarshal([]byte(req.Body), &resetPasswordReq); err != nil {
		logger.Error("Invalid request body: %v", err)
		return http.ErrorResponse(400, "invalid_request", "Invalid request body"), nil
	}

	// Validate required fields
	if resetPasswordReq.Email == "" || resetPasswordReq.Code == "" || resetPasswordReq.NewPassword == "" {
		return http.ErrorResponse(400, "missing_fields", "Email, code, and new password are required"), nil
	}

	// Call service
	err := h.passwordRecoveryService.ResetPassword(ctx, resetPasswordReq.Email, resetPasswordReq.Code, resetPasswordReq.NewPassword)
	if err != nil {
		switch {
		case errors.Is(err, services.ErrInvalidRecoveryCode):
			return http.ErrorResponse(422, "recovery_code_invalid", "Invalid recovery code"), nil
		case errors.Is(err, services.ErrExpiredRecoveryCode):
			return http.ErrorResponse(422, "recovery_code_expired", "Recovery code has expired"), nil
		case errors.Is(err, services.ErrPasswordPolicyViolation):
			return http.ErrorResponse(400, "password_policy_violation", "Password does not meet requirements"), nil
		case errors.Is(err, services.ErrTooManyAttempts):
			return http.ErrorResponse(429, "too_many_attempts", "Too many failed attempts. Please try again later."), nil
		case errors.Is(err, services.ErrLimitExceeded):
			return http.ErrorResponse(429, "limit_exceeded", "Rate limit exceeded. Please try again later."), nil
		case errors.Is(err, services.ErrUserNotFoundForRecovery):
			return http.ErrorResponse(404, "user_not_found", "User not found"), nil
		default:
			logger.Error("Reset password service error: %v", err)
			return http.ErrorResponse(500, "internal_error", "Internal server error"), nil
		}
	}

	// Prepare success response
	response := models.ResetPasswordResponse{
		Success: true,
	}

	body, err := json.Marshal(response)
	if err != nil {
		logger.Error("Failed to marshal response: %v", err)
		return http.ErrorResponse(500, "internal_error", "Failed to marshal response"), nil
	}

	return events.APIGatewayV2HTTPResponse{
		StatusCode: 200,
		Headers: map[string]string{
			"Content-Type": "application/json",
		},
		Body: string(body),
	}, nil
}
