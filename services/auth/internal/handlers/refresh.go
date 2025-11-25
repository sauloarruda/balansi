package handlers

import (
	"context"
	"encoding/json"
	"errors"
	"services/auth/internal/http"
	"services/auth/internal/logger"
	"services/auth/internal/services"
	"services/auth/internal/testhelpers"

	"github.com/aws/aws-lambda-go/events"
)

type RefreshHandler struct {
	sessionService testhelpers.SessionServiceInterface
}

func NewRefreshHandler(sessionService *services.SessionService) *RefreshHandler {
	return NewRefreshHandlerWithInterface(sessionService)
}

func NewRefreshHandlerWithInterface(sessionService testhelpers.SessionServiceInterface) *RefreshHandler {
	return &RefreshHandler{
		sessionService: sessionService,
	}
}

func (h *RefreshHandler) Handle(ctx context.Context, req events.APIGatewayV2HTTPRequest) (events.APIGatewayV2HTTPResponse, error) {
	// Extract session_id cookie from Cookies array (HTTP API v2 format)
	sessionID := http.ExtractCookieValue(req.Cookies, "session_id")

	if sessionID == "" {
		logger.Error("Missing session cookie. Cookies array length: %d", len(req.Cookies))
		return errorResponse(401, "unauthorized", "Missing session cookie"), nil
	}

	// Refresh access token
	accessTokenResp, err := h.sessionService.RefreshAccessToken(ctx, sessionID)
	if err != nil {
		switch {
		case errors.Is(err, services.ErrInvalidSession):
			return errorResponse(401, "invalid_session", "Invalid session"), nil
		case errors.Is(err, services.ErrUserNotConfirmed):
			return errorResponse(403, "user_not_confirmed", "User not confirmed"), nil
		case errors.Is(err, services.ErrRefreshTokenFailed):
			return errorResponse(401, "refresh_failed", "Failed to refresh token"), nil
		default:
			logger.Error("Refresh token error: %v", err)
			return errorResponse(500, "internal_error", "Internal server error"), nil
		}
	}

	// Prepare response
	body, err := json.Marshal(accessTokenResp)
	if err != nil {
		logger.Error("Failed to marshal response: %v", err)
		return errorResponse(500, "internal_error", "Failed to marshal response"), nil
	}

	return events.APIGatewayV2HTTPResponse{
		StatusCode: 200,
		Headers: map[string]string{
			"Content-Type": "application/json",
		},
		Body: string(body),
	}, nil
}
