package handlers

import (
	"context"
	"encoding/json"
	"strings"
	"testing"

	"services/auth/internal/models"

	"github.com/aws/aws-lambda-go/events"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// Helper function to create a test request
func createLogoutRequest() events.APIGatewayV2HTTPRequest {
	return events.APIGatewayV2HTTPRequest{
		RawPath: "/auth/logout",
		RequestContext: events.APIGatewayV2HTTPRequestContext{
			HTTP: events.APIGatewayV2HTTPRequestContextHTTPDescription{
				Method: "POST",
			},
		},
	}
}

// Helper function to unmarshal success response
func unmarshalLogoutResponse(t *testing.T, body string) models.LogoutResponse {
	var response models.LogoutResponse
	err := json.Unmarshal([]byte(body), &response)
	require.NoError(t, err)
	return response
}

func TestLogoutHandler_Handle_Success(t *testing.T) {
	handler := NewLogoutHandler()

	ctx := context.Background()
	req := createLogoutRequest()

	resp, err := handler.Handle(ctx, req)

	require.NoError(t, err)
	assert.Equal(t, 200, resp.StatusCode)
	assert.Equal(t, "application/json", resp.Headers["Content-Type"])

	// Verify response body
	response := unmarshalLogoutResponse(t, resp.Body)
	assert.True(t, response.Success)

	// Verify Set-Cookie header is present
	cookie := resp.Headers["Set-Cookie"]
	assert.NotEmpty(t, cookie)

	// Verify cookie clears session_id
	assert.Contains(t, cookie, "session_id=")
	assert.Contains(t, cookie, "Path=/")
	assert.Contains(t, cookie, "HttpOnly")
	assert.Contains(t, cookie, "Max-Age=-1")
}

func TestLogoutHandler_Handle_LocalDevelopment(t *testing.T) {
	handler := NewLogoutHandler()

	ctx := context.Background()
	req := createLogoutRequest()
	// Simulate local development (no domain)
	req.RequestContext.DomainName = ""

	resp, err := handler.Handle(ctx, req)

	require.NoError(t, err)
	assert.Equal(t, 200, resp.StatusCode)

	// Verify cookie has SameSite=Lax (for local development)
	cookie := resp.Headers["Set-Cookie"]
	assert.Contains(t, cookie, "SameSite=Lax")
	assert.NotContains(t, cookie, "SameSite=None")
	assert.NotContains(t, cookie, "Secure")
}

func TestLogoutHandler_Handle_Production(t *testing.T) {
	handler := NewLogoutHandler()

	ctx := context.Background()
	req := createLogoutRequest()
	// Simulate production (with domain)
	req.RequestContext.DomainName = "api.example.com"

	resp, err := handler.Handle(ctx, req)

	require.NoError(t, err)
	assert.Equal(t, 200, resp.StatusCode)

	// Verify cookie has SameSite=None and Secure (for production)
	cookie := resp.Headers["Set-Cookie"]
	assert.Contains(t, cookie, "SameSite=None")
	assert.Contains(t, cookie, "Secure")
	assert.NotContains(t, cookie, "SameSite=Lax")
}

func TestLogoutHandler_Handle_CookieFormat(t *testing.T) {
	handler := NewLogoutHandler()

	ctx := context.Background()
	req := createLogoutRequest()

	resp, err := handler.Handle(ctx, req)

	require.NoError(t, err)

	// Parse cookie attributes
	cookie := resp.Headers["Set-Cookie"]
	parts := strings.Split(cookie, ";")

	// Verify required attributes are present
	foundSessionID := false
	foundPath := false
	foundHttpOnly := false
	foundMaxAge := false

	for _, part := range parts {
		part = strings.TrimSpace(part)
		if strings.HasPrefix(part, "session_id=") {
			foundSessionID = true
		} else if part == "Path=/" {
			foundPath = true
		} else if part == "HttpOnly" {
			foundHttpOnly = true
		} else if part == "Max-Age=-1" {
			foundMaxAge = true
		}
	}

	assert.True(t, foundSessionID, "Cookie should contain session_id")
	assert.True(t, foundPath, "Cookie should contain Path=/")
	assert.True(t, foundHttpOnly, "Cookie should be HttpOnly")
	assert.True(t, foundMaxAge, "Cookie should have Max-Age=-1")
}
