package handlers

import (
	"context"
	"encoding/json"
	"services/auth/internal/http"
	"services/auth/internal/logger"
	"services/auth/internal/models"

	"github.com/aws/aws-lambda-go/events"
)

type LogoutHandler struct{}

func NewLogoutHandler() *LogoutHandler {
	return &LogoutHandler{}
}

func (h *LogoutHandler) Handle(ctx context.Context, req events.APIGatewayV2HTTPRequest) (events.APIGatewayV2HTTPResponse, error) {
	// Prepare success response
	response := models.LogoutResponse{
		Success: true,
	}

	body, err := json.Marshal(response)
	if err != nil {
		logger.Error("Failed to marshal response: %v", err)
		return http.ErrorResponse(500, "internal_error", "Failed to marshal response"), nil
	}

	// Build cookie header to expire the session_id cookie
	cookieHeader := buildLogoutCookieHeader(req)

	return events.APIGatewayV2HTTPResponse{
		StatusCode: 200,
		Headers: map[string]string{
			"Content-Type": "application/json",
			"Set-Cookie":   cookieHeader,
		},
		Body: string(body),
	}, nil
}

// buildLogoutCookieHeader builds a Set-Cookie header to expire the session_id cookie
func buildLogoutCookieHeader(req events.APIGatewayV2HTTPRequest) string {
	// Set Max-Age to -1 to immediately expire the cookie
	cookie := "session_id=; Path=/; HttpOnly; Max-Age=-1"

	isProduction := req.RequestContext.DomainName != "" && req.RequestContext.DomainName != "localhost"

	if isProduction {
		// In production (HTTPS), use SameSite=None with Secure
		cookie += "; SameSite=None; Secure"
	} else {
		// In local development (HTTP), use SameSite=Lax
		cookie += "; SameSite=Lax"
	}

	return cookie
}

