package handlers

import (
	"context"
	"encoding/json"
	"errors"
	"testing"

	"services/auth/internal/models"
	"services/auth/internal/services"
	"services/auth/internal/testhelpers"

	"github.com/aws/aws-lambda-go/events"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// Helper function to create a test request
func createForgotPasswordRequest(body string) events.APIGatewayV2HTTPRequest {
	return events.APIGatewayV2HTTPRequest{
		RawPath: "/auth/forgot-password",
		Body:    body,
		RequestContext: events.APIGatewayV2HTTPRequestContext{
			HTTP: events.APIGatewayV2HTTPRequestContextHTTPDescription{
				Method: "POST",
			},
		},
	}
}

// Helper function to unmarshal success response
func unmarshalForgotPasswordResponse(t *testing.T, body string) models.ForgotPasswordResponse {
	var response models.ForgotPasswordResponse
	err := json.Unmarshal([]byte(body), &response)
	require.NoError(t, err)
	return response
}

// Helper function to unmarshal error response
func unmarshalErrorResponse(t *testing.T, body string) models.ErrorResponse {
	var response models.ErrorResponse
	err := json.Unmarshal([]byte(body), &response)
	require.NoError(t, err)
	return response
}

func TestForgotPasswordHandler_Handle_Success(t *testing.T) {
	mockService := new(testhelpers.MockPasswordRecoveryService)
	handler := NewForgotPasswordHandlerWithInterface(mockService)

	ctx := context.Background()
	email := "user@example.com"
	req := createForgotPasswordRequest(`{"email": "` + email + `"}`)

	mockService.On("ForgotPassword", ctx, email).Return(nil)

	resp, err := handler.Handle(ctx, req)

	require.NoError(t, err)
	assert.Equal(t, 200, resp.StatusCode)
	assert.Equal(t, "application/json", resp.Headers["Content-Type"])

	response := unmarshalForgotPasswordResponse(t, resp.Body)
	assert.True(t, response.Success)
	assert.Equal(t, email, response.Destination)
	assert.Equal(t, "EMAIL", response.DeliveryMedium)

	mockService.AssertExpectations(t)
}

func TestForgotPasswordHandler_Handle_UserNotFound_EnumerationProtection(t *testing.T) {
	mockService := new(testhelpers.MockPasswordRecoveryService)
	handler := NewForgotPasswordHandlerWithInterface(mockService)

	ctx := context.Background()
	email := "nonexistent@example.com"
	req := createForgotPasswordRequest(`{"email": "` + email + `"}`)

	mockService.On("ForgotPassword", ctx, email).Return(services.ErrUserNotFoundForRecovery)

	resp, err := handler.Handle(ctx, req)

	require.NoError(t, err)
	// Should return 200 to prevent user enumeration
	assert.Equal(t, 200, resp.StatusCode)

	response := unmarshalForgotPasswordResponse(t, resp.Body)
	assert.True(t, response.Success)
	assert.Equal(t, email, response.Destination)

	mockService.AssertExpectations(t)
}

func TestForgotPasswordHandler_Handle_InvalidRequests(t *testing.T) {
	tests := []struct {
		name         string
		body         string
		expectedCode string
		expectedMsg  string
	}{
		{
			name:         "InvalidJSON",
			body:         `{"invalid": json}`,
			expectedCode: "invalid_request",
			expectedMsg:  "Invalid request body",
		},
		{
			name:         "MissingEmail",
			body:         `{}`,
			expectedCode: "missing_fields",
			expectedMsg:  "Email is required",
		},
		{
			name:         "EmptyBody",
			body:         "",
			expectedCode: "invalid_request",
			expectedMsg:  "", // Don't check message for empty body
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			mockService := new(testhelpers.MockPasswordRecoveryService)
			handler := NewForgotPasswordHandlerWithInterface(mockService)

			req := createForgotPasswordRequest(tt.body)
			resp, err := handler.Handle(context.Background(), req)

			require.NoError(t, err)
			assert.Equal(t, 400, resp.StatusCode)

			errorResp := unmarshalErrorResponse(t, resp.Body)
			assert.Equal(t, tt.expectedCode, errorResp.Code)
			if tt.expectedMsg != "" {
				assert.Contains(t, errorResp.Message, tt.expectedMsg)
			}

			mockService.AssertNotCalled(t, "ForgotPassword")
		})
	}
}

func TestForgotPasswordHandler_Handle_RateLimitErrors(t *testing.T) {
	tests := []struct {
		name         string
		serviceError error
		expectedCode string
		expectedMsg  string
	}{
		{
			name:         "TooManyAttempts",
			serviceError: services.ErrTooManyAttempts,
			expectedCode: "too_many_attempts",
			expectedMsg:  "Too many attempts",
		},
		{
			name:         "LimitExceeded",
			serviceError: services.ErrLimitExceeded,
			expectedCode: "limit_exceeded",
			expectedMsg:  "Rate limit exceeded",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			mockService := new(testhelpers.MockPasswordRecoveryService)
			handler := NewForgotPasswordHandlerWithInterface(mockService)

			ctx := context.Background()
			email := "user@example.com"
			req := createForgotPasswordRequest(`{"email": "` + email + `"}`)

			mockService.On("ForgotPassword", ctx, email).Return(tt.serviceError)

			resp, err := handler.Handle(ctx, req)

			require.NoError(t, err)
			assert.Equal(t, 429, resp.StatusCode)

			errorResp := unmarshalErrorResponse(t, resp.Body)
			assert.Equal(t, tt.expectedCode, errorResp.Code)
			assert.Contains(t, errorResp.Message, tt.expectedMsg)

			mockService.AssertExpectations(t)
		})
	}
}

func TestForgotPasswordHandler_Handle_ServiceError(t *testing.T) {
	mockService := new(testhelpers.MockPasswordRecoveryService)
	handler := NewForgotPasswordHandlerWithInterface(mockService)

	ctx := context.Background()
	email := "user@example.com"
	req := createForgotPasswordRequest(`{"email": "` + email + `"}`)

	mockService.On("ForgotPassword", ctx, email).Return(errors.New("internal service error"))

	resp, err := handler.Handle(ctx, req)

	require.NoError(t, err)
	assert.Equal(t, 500, resp.StatusCode)

	errorResp := unmarshalErrorResponse(t, resp.Body)
	assert.Equal(t, "internal_error", errorResp.Code)
	assert.Contains(t, errorResp.Message, "Internal server error")

	mockService.AssertExpectations(t)
}
