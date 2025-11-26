package handlers

import (
	"context"
	"encoding/json"
	"errors"
	"services/auth/internal/http"
	"services/auth/internal/logger"
	"services/auth/internal/models"
	"services/auth/internal/services"
	"services/auth/internal/testhelpers"

	"github.com/aws/aws-lambda-go/events"
)

// PasswordRecoveryServiceInterface defines the interface for password recovery service (aliased for convenience).
type PasswordRecoveryServiceInterface = testhelpers.PasswordRecoveryServiceInterface

type ForgotPasswordHandler struct {
	passwordRecoveryService PasswordRecoveryServiceInterface
}

func NewForgotPasswordHandler(passwordRecoveryService *services.PasswordRecoveryService) *ForgotPasswordHandler {
	return NewForgotPasswordHandlerWithInterface(passwordRecoveryService)
}

// NewForgotPasswordHandlerWithInterface creates a handler with an interface-based service
// This allows for easier testing with mocks.
func NewForgotPasswordHandlerWithInterface(passwordRecoveryService PasswordRecoveryServiceInterface) *ForgotPasswordHandler {
	return &ForgotPasswordHandler{
		passwordRecoveryService: passwordRecoveryService,
	}
}

func (h *ForgotPasswordHandler) Handle(ctx context.Context, req events.APIGatewayV2HTTPRequest) (events.APIGatewayV2HTTPResponse, error) {
	// Parse request body
	var forgotPasswordReq models.ForgotPasswordRequest
	if err := json.Unmarshal([]byte(req.Body), &forgotPasswordReq); err != nil {
		logger.Error("Invalid request body: %v", err)
		return http.ErrorResponse(400, "invalid_request", "Invalid request body"), nil
	}

	// Validate email field
	if forgotPasswordReq.Email == "" {
		return http.ErrorResponse(400, "missing_fields", "Email is required"), nil
	}

	// Call service
	err := h.passwordRecoveryService.ForgotPassword(ctx, forgotPasswordReq.Email)
	if err != nil {
		// For security (user enumeration protection), we always return 200 to the client
		// but log the error for debugging
		if errors.Is(err, services.ErrUserNotFoundForRecovery) {
			logger.Info("Password recovery requested for non-existent user (enumeration protection applied)")
		} else if errors.Is(err, services.ErrTooManyAttempts) {
			logger.Warn("Password recovery rate limit exceeded for email: %s", forgotPasswordReq.Email)
			return http.ErrorResponse(429, "too_many_attempts", "Too many attempts. Please try again later."), nil
		} else if errors.Is(err, services.ErrLimitExceeded) {
			logger.Warn("Password recovery limit exceeded for email: %s", forgotPasswordReq.Email)
			return http.ErrorResponse(429, "limit_exceeded", "Rate limit exceeded. Please try again later."), nil
		} else {
			logger.Error("Password recovery service error: %v", err)
			return http.ErrorResponse(500, "internal_error", "Internal server error"), nil
		}
	}

	// Always return success to prevent user enumeration
	// Even if user doesn't exist, we return 200 with a generic success message
	// Safe to echo back the email from request - doesn't reveal if user exists
	response := models.ForgotPasswordResponse{
		Success:        true,
		Destination:    forgotPasswordReq.Email,
		DeliveryMedium: "EMAIL",
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
