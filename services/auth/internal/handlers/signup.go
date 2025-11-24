package handlers

import (
	"context"
	"encoding/json"
	"errors"
	"services/auth/internal/logger"
	"services/auth/internal/models"
	"services/auth/internal/services"
	"services/auth/internal/testhelpers"

	"github.com/aws/aws-lambda-go/events"
)

// SignupServiceInterface defines the interface for signup service (aliased for convenience).
type SignupServiceInterface = testhelpers.SignupServiceInterface

type SignupHandler struct {
	signupService SignupServiceInterface
}

func NewSignupHandler(signupService *services.SignupService) *SignupHandler {
	return NewSignupHandlerWithInterface(signupService)
}

// NewSignupHandlerWithInterface creates a handler with an interface-based service
// This allows for easier testing with mocks.
func NewSignupHandlerWithInterface(signupService SignupServiceInterface) *SignupHandler {
	return &SignupHandler{
		signupService: signupService,
	}
}

func (h *SignupHandler) Handle(ctx context.Context, req events.APIGatewayV2HTTPRequest) (events.APIGatewayV2HTTPResponse, error) {
	// Parse request body
	var signupReq models.SignupRequest
	if err := json.Unmarshal([]byte(req.Body), &signupReq); err != nil {
		// Log detailed error for debugging but return generic message to client
		logger.Error("Invalid request body: %v", err)
		return errorResponse(400, "invalid_request", "Invalid request body"), nil
	}

	// Validate fields
	if signupReq.Name == "" || signupReq.Email == "" {
		return errorResponse(400, "missing_fields", "Name and email are required"), nil
	}

	// Call service
	result, err := h.signupService.Signup(ctx, signupReq.Name, signupReq.Email)
	if err != nil {
		switch {
		case errors.Is(err, services.ErrUserAlreadyExists):
			return errorResponse(409, "user_exists", "User with this email already exists"), nil
		default:
			// Log the actual error for debugging but return generic message to client
			logger.Error("Signup service error: %v", err)
			return errorResponse(500, "internal_error", "Internal server error"), nil
		}
	}

	// Prepare response
	response := models.SignupResponse{
		ID:     result.User.ID,
		Name:   result.User.Name,
		Email:  result.User.Email,
		Status: result.Status,
	}

	body, err := json.Marshal(response)
	if err != nil {
		logger.Error("Failed to marshal response: %v", err)
		return errorResponse(500, "internal_error", "Failed to marshal response"), nil
	}

	// All new signups require email confirmation, so return 200
	statusCode := 200

	return events.APIGatewayV2HTTPResponse{
		StatusCode: statusCode,
		Headers: map[string]string{
			"Content-Type": "application/json",
		},
		Body: string(body),
	}, nil
}

func errorResponse(statusCode int, code, message string) events.APIGatewayV2HTTPResponse {
	payload := models.ErrorResponse{
		Code:    code,
		Message: message,
	}

	body, _ := json.Marshal(payload)
	return events.APIGatewayV2HTTPResponse{
		StatusCode: statusCode,
		Headers: map[string]string{
			"Content-Type": "application/json",
		},
		Body: string(body),
	}
}
