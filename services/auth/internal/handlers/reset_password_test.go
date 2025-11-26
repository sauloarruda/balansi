package handlers

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"testing"

	"services/auth/internal/models"
	"services/auth/internal/services"
	"services/auth/internal/testhelpers"

	"github.com/aws/aws-lambda-go/events"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// Helper function to create a test request
func createResetPasswordRequest(body string) events.APIGatewayV2HTTPRequest {
	return events.APIGatewayV2HTTPRequest{
		RawPath: "/auth/reset-password",
		Body:    body,
		RequestContext: events.APIGatewayV2HTTPRequestContext{
			HTTP: events.APIGatewayV2HTTPRequestContextHTTPDescription{
				Method: "POST",
			},
		},
	}
}

// Helper function to create a valid reset password request body
func createResetPasswordBody(email, code, password string) string {
	return fmt.Sprintf(`{"email": "%s", "code": "%s", "newPassword": "%s"}`, email, code, password)
}

// Helper function to unmarshal success response
func unmarshalResetPasswordResponse(t *testing.T, body string) models.ResetPasswordResponse {
	var response models.ResetPasswordResponse
	err := json.Unmarshal([]byte(body), &response)
	require.NoError(t, err)
	return response
}

// Helper function to unmarshal error response (reused from forgot_password_test.go)
func unmarshalResetPasswordErrorResponse(t *testing.T, body string) models.ErrorResponse {
	var response models.ErrorResponse
	err := json.Unmarshal([]byte(body), &response)
	require.NoError(t, err)
	return response
}

func TestResetPasswordHandler_Handle_Success(t *testing.T) {
	mockService := new(testhelpers.MockPasswordRecoveryService)
	handler := NewResetPasswordHandlerWithInterface(mockService)

	ctx := context.Background()
	email := "user@example.com"
	code := "123456"
	password := "NewP@ssw0rd"
	req := createResetPasswordRequest(createResetPasswordBody(email, code, password))

	mockService.On("ResetPassword", ctx, email, code, password).Return(nil)

	resp, err := handler.Handle(ctx, req)

	require.NoError(t, err)
	assert.Equal(t, 200, resp.StatusCode)
	assert.Equal(t, "application/json", resp.Headers["Content-Type"])

	response := unmarshalResetPasswordResponse(t, resp.Body)
	assert.True(t, response.Success)

	mockService.AssertExpectations(t)
}

func TestResetPasswordHandler_Handle_InvalidRequests(t *testing.T) {
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
			body:         `{"code": "123456", "newPassword": "NewP@ssw0rd"}`,
			expectedCode: "missing_fields",
			expectedMsg:  "Email, code, and new password are required",
		},
		{
			name:         "MissingCode",
			body:         `{"email": "user@example.com", "newPassword": "NewP@ssw0rd"}`,
			expectedCode: "missing_fields",
			expectedMsg:  "Email, code, and new password are required",
		},
		{
			name:         "MissingPassword",
			body:         `{"email": "user@example.com", "code": "123456"}`,
			expectedCode: "missing_fields",
			expectedMsg:  "Email, code, and new password are required",
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
			handler := NewResetPasswordHandlerWithInterface(mockService)

			req := createResetPasswordRequest(tt.body)
			resp, err := handler.Handle(context.Background(), req)

			require.NoError(t, err)
			assert.Equal(t, 400, resp.StatusCode)

			errorResp := unmarshalResetPasswordErrorResponse(t, resp.Body)
			assert.Equal(t, tt.expectedCode, errorResp.Code)
			if tt.expectedMsg != "" {
				assert.Contains(t, errorResp.Message, tt.expectedMsg)
			}

			mockService.AssertNotCalled(t, "ResetPassword")
		})
	}
}

func TestResetPasswordHandler_Handle_CodeValidationErrors(t *testing.T) {
	tests := []struct {
		name         string
		serviceError error
		expectedCode string
		expectedMsg  string
		statusCode   int
	}{
		{
			name:         "InvalidCode",
			serviceError: services.ErrInvalidRecoveryCode,
			expectedCode: "recovery_code_invalid",
			expectedMsg:  "Invalid recovery code",
			statusCode:   422,
		},
		{
			name:         "ExpiredCode",
			serviceError: services.ErrExpiredRecoveryCode,
			expectedCode: "recovery_code_expired",
			expectedMsg:  "Recovery code has expired",
			statusCode:   422,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			mockService := new(testhelpers.MockPasswordRecoveryService)
			handler := NewResetPasswordHandlerWithInterface(mockService)

			ctx := context.Background()
			email := "user@example.com"
			code := "123456"
			password := "NewP@ssw0rd"
			req := createResetPasswordRequest(createResetPasswordBody(email, code, password))

			mockService.On("ResetPassword", ctx, email, code, password).Return(tt.serviceError)

			resp, err := handler.Handle(ctx, req)

			require.NoError(t, err)
			assert.Equal(t, tt.statusCode, resp.StatusCode)

			errorResp := unmarshalResetPasswordErrorResponse(t, resp.Body)
			assert.Equal(t, tt.expectedCode, errorResp.Code)
			assert.Contains(t, errorResp.Message, tt.expectedMsg)

			mockService.AssertExpectations(t)
		})
	}
}

func TestResetPasswordHandler_Handle_PasswordPolicyViolation(t *testing.T) {
	mockService := new(testhelpers.MockPasswordRecoveryService)
	handler := NewResetPasswordHandlerWithInterface(mockService)

	ctx := context.Background()
	email := "user@example.com"
	code := "123456"
	weakPassword := "weak"
	req := createResetPasswordRequest(createResetPasswordBody(email, code, weakPassword))

	mockService.On("ResetPassword", ctx, email, code, weakPassword).Return(services.ErrPasswordPolicyViolation)

	resp, err := handler.Handle(ctx, req)

	require.NoError(t, err)
	assert.Equal(t, 400, resp.StatusCode)

	errorResp := unmarshalResetPasswordErrorResponse(t, resp.Body)
	assert.Equal(t, "password_policy_violation", errorResp.Code)
	assert.Contains(t, errorResp.Message, "Password does not meet requirements")

	mockService.AssertExpectations(t)
}

func TestResetPasswordHandler_Handle_RateLimitErrors(t *testing.T) {
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
			expectedMsg:  "Too many failed attempts",
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
			handler := NewResetPasswordHandlerWithInterface(mockService)

			ctx := context.Background()
			email := "user@example.com"
			code := "123456"
			password := "NewP@ssw0rd"
			req := createResetPasswordRequest(createResetPasswordBody(email, code, password))

			mockService.On("ResetPassword", ctx, email, code, password).Return(tt.serviceError)

			resp, err := handler.Handle(ctx, req)

			require.NoError(t, err)
			assert.Equal(t, 429, resp.StatusCode)

			errorResp := unmarshalResetPasswordErrorResponse(t, resp.Body)
			assert.Equal(t, tt.expectedCode, errorResp.Code)
			assert.Contains(t, errorResp.Message, tt.expectedMsg)

			mockService.AssertExpectations(t)
		})
	}
}

func TestResetPasswordHandler_Handle_UserNotFound(t *testing.T) {
	mockService := new(testhelpers.MockPasswordRecoveryService)
	handler := NewResetPasswordHandlerWithInterface(mockService)

	ctx := context.Background()
	email := "nonexistent@example.com"
	code := "123456"
	password := "NewP@ssw0rd"
	req := createResetPasswordRequest(createResetPasswordBody(email, code, password))

	mockService.On("ResetPassword", ctx, email, code, password).Return(services.ErrUserNotFoundForRecovery)

	resp, err := handler.Handle(ctx, req)

	require.NoError(t, err)
	assert.Equal(t, 404, resp.StatusCode)

	errorResp := unmarshalResetPasswordErrorResponse(t, resp.Body)
	assert.Equal(t, "user_not_found", errorResp.Code)
	assert.Contains(t, errorResp.Message, "User not found")

	mockService.AssertExpectations(t)
}

func TestResetPasswordHandler_Handle_ServiceError(t *testing.T) {
	mockService := new(testhelpers.MockPasswordRecoveryService)
	handler := NewResetPasswordHandlerWithInterface(mockService)

	ctx := context.Background()
	email := "user@example.com"
	code := "123456"
	password := "NewP@ssw0rd"
	req := createResetPasswordRequest(createResetPasswordBody(email, code, password))

	mockService.On("ResetPassword", ctx, email, code, password).Return(errors.New("internal service error"))

	resp, err := handler.Handle(ctx, req)

	require.NoError(t, err)
	assert.Equal(t, 500, resp.StatusCode)

	errorResp := unmarshalResetPasswordErrorResponse(t, resp.Body)
	assert.Equal(t, "internal_error", errorResp.Code)
	assert.Contains(t, errorResp.Message, "Internal server error")

	mockService.AssertExpectations(t)
}
