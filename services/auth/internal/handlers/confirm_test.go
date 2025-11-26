package handlers

import (
	"context"
	"encoding/json"
	"errors"
	"services/auth/internal/models"
	"services/auth/internal/services"
	"services/auth/internal/testhelpers"
	"testing"

	"github.com/aws/aws-lambda-go/events"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestConfirmHandler_Handle_Success(t *testing.T) {
	mockService := new(testhelpers.MockSignupService)
	mockSessionService := new(testhelpers.MockSessionService)
	handler := NewConfirmHandlerWithInterface(mockService, mockSessionService)

	ctx := context.Background()
	reqBody := `{"userId": 1, "code": "123456"}`
	req := events.APIGatewayV2HTTPRequest{
		Body: reqBody,
		Headers: map[string]string{
			"origin": "https://example.com",
		},
		RequestContext: events.APIGatewayV2HTTPRequestContext{
			DomainName: "api.example.com",
		},
	}

	expectedResult := &models.AuthenticationTokenResult{
		RefreshToken: "refresh-token-123",
		UserID:       1,
		Username:     "testuser",
	}

	mockService.On("Confirm", ctx, int64(1), "123456").Return(expectedResult, nil)
	mockSessionService.On("CreateSessionCookie", "refresh-token-123", int64(1), "testuser", req).Return("session_id=encrypted-session-data; Path=/; HttpOnly; Max-Age=2592000; SameSite=Lax", nil)

	resp, err := handler.Handle(ctx, req)

	require.NoError(t, err)
	assert.Equal(t, 200, resp.StatusCode)
	assert.Equal(t, "application/json", resp.Headers["Content-Type"])
	assert.Equal(t, "session_id=encrypted-session-data; Path=/; HttpOnly; Max-Age=2592000; SameSite=Lax", resp.Headers["Set-Cookie"])

	var successResp map[string]interface{}
	err = json.Unmarshal([]byte(resp.Body), &successResp)
	require.NoError(t, err)
	assert.Equal(t, true, successResp["success"])

	mockService.AssertExpectations(t)
	mockSessionService.AssertExpectations(t)
}

func TestConfirmHandler_Handle_UserNotFound(t *testing.T) {
	mockService := new(testhelpers.MockSignupService)
	mockSessionService := new(testhelpers.MockSessionService)
	handler := NewConfirmHandlerWithInterface(mockService, mockSessionService)

	ctx := context.Background()
	reqBody := `{"userId": 999, "code": "123456"}`
	req := events.APIGatewayV2HTTPRequest{
		Body: reqBody,
	}

	mockService.On("Confirm", ctx, int64(999), "123456").
		Return(nil, services.ErrUserNotFound)

	resp, err := handler.Handle(ctx, req)

	require.NoError(t, err)
	assert.Equal(t, 404, resp.StatusCode)

	var errorResp models.ErrorResponse
	err = json.Unmarshal([]byte(resp.Body), &errorResp)
	require.NoError(t, err)
	assert.Equal(t, "user_not_found", errorResp.Code)
	assert.Equal(t, "User not found", errorResp.Message)

	mockService.AssertExpectations(t)
}

func TestConfirmHandler_Handle_UserAlreadyConfirmed(t *testing.T) {
	mockService := new(testhelpers.MockSignupService)
	mockSessionService := new(testhelpers.MockSessionService)
	handler := NewConfirmHandlerWithInterface(mockService, mockSessionService)

	ctx := context.Background()
	reqBody := `{"userId": 1, "code": "123456"}`
	req := events.APIGatewayV2HTTPRequest{
		Body: reqBody,
	}

	mockService.On("Confirm", ctx, int64(1), "123456").
		Return(nil, services.ErrUserAlreadyConfirmed)

	resp, err := handler.Handle(ctx, req)

	require.NoError(t, err)
	assert.Equal(t, 409, resp.StatusCode)

	var errorResp models.ErrorResponse
	err = json.Unmarshal([]byte(resp.Body), &errorResp)
	require.NoError(t, err)
	assert.Equal(t, "user_already_confirmed", errorResp.Code)
	assert.Equal(t, "User is already confirmed", errorResp.Message)

	mockService.AssertExpectations(t)
}

func TestConfirmHandler_Handle_InvalidCode(t *testing.T) {
	mockService := new(testhelpers.MockSignupService)
	mockSessionService := new(testhelpers.MockSessionService)
	handler := NewConfirmHandlerWithInterface(mockService, mockSessionService)

	ctx := context.Background()
	reqBody := `{"userId": 1, "code": "wrong-code"}`
	req := events.APIGatewayV2HTTPRequest{
		Body: reqBody,
	}

	mockService.On("Confirm", ctx, int64(1), "wrong-code").
		Return(nil, services.ErrInvalidConfirmationCode)

	resp, err := handler.Handle(ctx, req)

	require.NoError(t, err)
	assert.Equal(t, 422, resp.StatusCode)

	var errorResp models.ErrorResponse
	err = json.Unmarshal([]byte(resp.Body), &errorResp)
	require.NoError(t, err)
	assert.Equal(t, "invalid_code", errorResp.Code)
	assert.Equal(t, "Incorrect confirmation code", errorResp.Message)

	mockService.AssertExpectations(t)
}

func TestConfirmHandler_Handle_ExpiredCode(t *testing.T) {
	mockService := new(testhelpers.MockSignupService)
	mockSessionService := new(testhelpers.MockSessionService)
	handler := NewConfirmHandlerWithInterface(mockService, mockSessionService)

	ctx := context.Background()
	reqBody := `{"userId": 1, "code": "expired-code"}`
	req := events.APIGatewayV2HTTPRequest{
		Body: reqBody,
	}

	mockService.On("Confirm", ctx, int64(1), "expired-code").
		Return(nil, services.ErrExpiredConfirmationCode)

	resp, err := handler.Handle(ctx, req)

	require.NoError(t, err)
	assert.Equal(t, 422, resp.StatusCode)

	var errorResp models.ErrorResponse
	err = json.Unmarshal([]byte(resp.Body), &errorResp)
	require.NoError(t, err)
	assert.Equal(t, "expired_code", errorResp.Code)
	assert.Equal(t, "Confirmation code expired", errorResp.Message)

	mockService.AssertExpectations(t)
}

func TestConfirmHandler_Handle_InternalError(t *testing.T) {
	mockService := new(testhelpers.MockSignupService)
	mockSessionService := new(testhelpers.MockSessionService)
	handler := NewConfirmHandlerWithInterface(mockService, mockSessionService)

	ctx := context.Background()
	reqBody := `{"userId": 1, "code": "123456"}`
	req := events.APIGatewayV2HTTPRequest{
		Body: reqBody,
	}

	mockService.On("Confirm", ctx, int64(1), "123456").
		Return(nil, errors.New("unexpected error"))

	resp, err := handler.Handle(ctx, req)

	require.NoError(t, err)
	assert.Equal(t, 500, resp.StatusCode)

	var errorResp models.ErrorResponse
	err = json.Unmarshal([]byte(resp.Body), &errorResp)
	require.NoError(t, err)
	assert.Equal(t, "internal_error", errorResp.Code)
	assert.Equal(t, "Internal server error", errorResp.Message)

	mockService.AssertExpectations(t)
}

func TestConfirmHandler_Handle_Validation(t *testing.T) {
	mockService := new(testhelpers.MockSignupService)
	mockSessionService := new(testhelpers.MockSessionService)
	handler := NewConfirmHandlerWithInterface(mockService, mockSessionService)
	ctx := context.Background()

	tests := []struct {
		name           string
		body           string
		expectedStatus int
		expectedCode   string
	}{
		{
			name:           "invalid json",
			body:           `{invalid}`,
			expectedStatus: 400,
			expectedCode:   "invalid_request",
		},
		{
			name:           "missing user id",
			body:           `{"code": "123456"}`,
			expectedStatus: 400,
			expectedCode:   "missing_fields",
		},
		{
			name:           "missing code",
			body:           `{"userId": 1}`,
			expectedStatus: 400,
			expectedCode:   "missing_fields",
		},
		{
			name:           "zero user id",
			body:           `{"userId": 0, "code": "123456"}`,
			expectedStatus: 400,
			expectedCode:   "missing_fields",
		},
		{
			name:           "empty code",
			body:           `{"userId": 1, "code": ""}`,
			expectedStatus: 400,
			expectedCode:   "missing_fields",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			req := events.APIGatewayV2HTTPRequest{
				Body: tt.body,
			}

			resp, err := handler.Handle(ctx, req)
			assert.NoError(t, err)
			assert.Equal(t, tt.expectedStatus, resp.StatusCode)

			var errorResp models.ErrorResponse
			err = json.Unmarshal([]byte(resp.Body), &errorResp)
			assert.NoError(t, err)
			assert.Equal(t, tt.expectedCode, errorResp.Code)

			// Service should not be called for validation errors
			mockService.AssertNotCalled(t, "Confirm")
		})
	}
}
