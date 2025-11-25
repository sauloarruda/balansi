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

type ConfirmHandler struct {
	signupService  testhelpers.SignupServiceInterface
	sessionService testhelpers.SessionServiceInterface
}

func NewConfirmHandler(signupService *services.SignupService, sessionService *services.SessionService) *ConfirmHandler {
	return NewConfirmHandlerWithInterface(signupService, sessionService)
}

// NewConfirmHandlerWithInterface creates a handler with an interface-based service
// This allows for easier testing with mocks.
func NewConfirmHandlerWithInterface(signupService testhelpers.SignupServiceInterface, sessionService testhelpers.SessionServiceInterface) *ConfirmHandler {
	return &ConfirmHandler{
		signupService:  signupService,
		sessionService: sessionService,
	}
}

func (h *ConfirmHandler) Handle(ctx context.Context, req events.APIGatewayV2HTTPRequest) (events.APIGatewayV2HTTPResponse, error) {
	// Parse request body
	var confirmReq models.ConfirmRequest
	if err := json.Unmarshal([]byte(req.Body), &confirmReq); err != nil {
		logger.Error("Invalid request body: %v", err)
		return errorResponse(400, "invalid_request", "Invalid request body"), nil
	}

	// Validate fields
	// Note: UserID <= 0 catches both omitted fields (which unmarshal to 0) and explicit zero values.
	// This is safe because user IDs must be positive. If we add more fields in the future,
	// consider using pointer types (*int64) or a validation library for better field-level error messages.
	if confirmReq.UserID <= 0 || confirmReq.Code == "" {
		return errorResponse(400, "missing_fields", "User ID and code are required"), nil
	}

	// Call service
	confirmResult, err := h.signupService.Confirm(ctx, confirmReq.UserID, confirmReq.Code)
	if err != nil {
		switch {
		case errors.Is(err, services.ErrUserNotFound):
			return errorResponse(404, "user_not_found", "User not found"), nil
		case errors.Is(err, services.ErrUserAlreadyConfirmed):
			return errorResponse(409, "user_already_confirmed", "User is already confirmed"), nil
		case errors.Is(err, services.ErrInvalidConfirmationCode):
			return errorResponse(422, "invalid_code", "Incorrect confirmation code"), nil
		case errors.Is(err, services.ErrExpiredConfirmationCode):
			return errorResponse(422, "expired_code", "Confirmation code expired"), nil
		default:
			// Log the actual error for debugging
			logger.Error("Confirm service error: %v", err)
			return errorResponse(500, "internal_error", "Internal server error"), nil
		}
	}

	// Create session cookie data
	sessionData := &models.SessionCookieData{
		RefreshToken: confirmResult.RefreshToken,
		UserID:       confirmResult.UserID,
		Username:     confirmResult.Username,
	}

	// Encrypt session data for cookie
	encryptedSessionData, err := h.sessionService.EncryptSessionData(sessionData)
	if err != nil {
		logger.Error("Failed to encrypt session data: %v", err)
		return errorResponse(500, "internal_error", "Failed to create session"), nil
	}

	// Create cookie header
	// Cookie expires in 30 days (same as Cognito refresh token)
	cookieValue := http.BuildCookieHeader(encryptedSessionData, "session_id", req)

	// Log cookie configuration for debugging
	origin := req.Headers["origin"]
	if origin == "" {
		origin = req.Headers["Origin"]
	}
	logger.Info("Setting cookie - Origin: %s, API Domain: %s", origin, req.RequestContext.DomainName)

	// Return success response with cookie
	return events.APIGatewayV2HTTPResponse{
		StatusCode: 200,
		Headers: map[string]string{
			"Content-Type": "application/json",
			"Set-Cookie":   cookieValue,
		},
		Body: `{"success": true}`,
	}, nil
}
