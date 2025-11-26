package handlers

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"time"
	"services/auth/internal/models"
	"services/auth/internal/services"
	"services/auth/internal/testhelpers"
	"testing"

	"github.com/aws/aws-lambda-go/events"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
)

// Helper functions
func setupConfirmHandler(t *testing.T) (*testhelpers.MockSignupService, *testhelpers.MockSessionService, *ConfirmHandler) {
	t.Helper()
	mockService := new(testhelpers.MockSignupService)
	mockSessionService := new(testhelpers.MockSessionService)
	handler := NewConfirmHandlerWithInterface(mockService, mockSessionService)
	return mockService, mockSessionService, handler
}

func assertErrorResponse(t *testing.T, resp events.APIGatewayV2HTTPResponse, expectedStatus int, expectedCode string) {
	t.Helper()
	assert.Equal(t, expectedStatus, resp.StatusCode)

	var errorResp models.ErrorResponse
	err := json.Unmarshal([]byte(resp.Body), &errorResp)
	require.NoError(t, err)
	assert.Equal(t, expectedCode, errorResp.Code)
}

func assertSuccessResponse(t *testing.T, resp events.APIGatewayV2HTTPResponse, expectedCookie string) {
	t.Helper()
	assert.Equal(t, 200, resp.StatusCode)
	assert.Equal(t, "application/json", resp.Headers["Content-Type"])
	if expectedCookie != "" {
		assert.Equal(t, expectedCookie, resp.Headers["Set-Cookie"])
	}

	var successResp map[string]interface{}
	err := json.Unmarshal([]byte(resp.Body), &successResp)
	require.NoError(t, err)
	assert.Equal(t, true, successResp["success"])
}

// Success scenarios
func TestConfirmHandler_Handle_Success(t *testing.T) {
	t.Parallel()

	mockService, mockSessionService, handler := setupConfirmHandler(t)
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

	expectedCookie := "session_id=encrypted-session-data; Path=/; HttpOnly; Max-Age=2592000; SameSite=Lax"

	mockService.On("Confirm", ctx, int64(1), "123456").Return(expectedResult, nil)
	mockSessionService.On("CreateSessionCookie", "refresh-token-123", int64(1), "testuser", req).Return(expectedCookie, nil)

	resp, err := handler.Handle(ctx, req)

	require.NoError(t, err)
	assertSuccessResponse(t, resp, expectedCookie)

	mockService.AssertExpectations(t)
	mockSessionService.AssertExpectations(t)
}

func TestConfirmHandler_Handle_SuccessMinimalRequest(t *testing.T) {
	t.Parallel()

	mockService, mockSessionService, handler := setupConfirmHandler(t)
	ctx := context.Background()

	req := events.APIGatewayV2HTTPRequest{
		Body: `{"userId": 2, "code": "654321"}`,
	}

	expectedResult := &models.AuthenticationTokenResult{
		RefreshToken: "token-456",
		UserID:       2,
		Username:     "user2",
	}

	mockService.On("Confirm", ctx, int64(2), "654321").Return(expectedResult, nil)
	mockSessionService.On("CreateSessionCookie", mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return("cookie", nil)

	resp, err := handler.Handle(ctx, req)

	require.NoError(t, err)
	assert.Equal(t, 200, resp.StatusCode)

	mockService.AssertExpectations(t)
	mockSessionService.AssertExpectations(t)
}

// Error scenarios
func TestConfirmHandler_Handle_UserNotFound(t *testing.T) {
	t.Parallel()

	mockService, _, handler := setupConfirmHandler(t)
	ctx := context.Background()

	req := events.APIGatewayV2HTTPRequest{
		Body: `{"userId": 999, "code": "123456"}`,
	}

	mockService.On("Confirm", ctx, int64(999), "123456").
		Return(nil, services.ErrUserNotFound)

	resp, err := handler.Handle(ctx, req)

	require.NoError(t, err)
	assertErrorResponse(t, resp, 404, "user_not_found")

	mockService.AssertExpectations(t)
}

func TestConfirmHandler_Handle_UserAlreadyConfirmed(t *testing.T) {
	t.Parallel()

	mockService, _, handler := setupConfirmHandler(t)
	ctx := context.Background()

	req := events.APIGatewayV2HTTPRequest{
		Body: `{"userId": 1, "code": "123456"}`,
	}

	mockService.On("Confirm", ctx, int64(1), "123456").
		Return(nil, services.ErrUserAlreadyConfirmed)

	resp, err := handler.Handle(ctx, req)

	require.NoError(t, err)
	assertErrorResponse(t, resp, 409, "user_already_confirmed")

	mockService.AssertExpectations(t)
}

func TestConfirmHandler_Handle_InvalidCode(t *testing.T) {
	t.Parallel()

	mockService, _, handler := setupConfirmHandler(t)
	ctx := context.Background()

	req := events.APIGatewayV2HTTPRequest{
		Body: `{"userId": 1, "code": "wrong-code"}`,
	}

	mockService.On("Confirm", ctx, int64(1), "wrong-code").
		Return(nil, services.ErrInvalidConfirmationCode)

	resp, err := handler.Handle(ctx, req)

	require.NoError(t, err)
	assertErrorResponse(t, resp, 422, "invalid_code")

	mockService.AssertExpectations(t)
}

func TestConfirmHandler_Handle_ExpiredCode(t *testing.T) {
	t.Parallel()

	mockService, _, handler := setupConfirmHandler(t)
	ctx := context.Background()

	req := events.APIGatewayV2HTTPRequest{
		Body: `{"userId": 1, "code": "expired-code"}`,
	}

	mockService.On("Confirm", ctx, int64(1), "expired-code").
		Return(nil, services.ErrExpiredConfirmationCode)

	resp, err := handler.Handle(ctx, req)

	require.NoError(t, err)
	assertErrorResponse(t, resp, 422, "expired_code")

	mockService.AssertExpectations(t)
}

func TestConfirmHandler_Handle_InternalError(t *testing.T) {
	t.Parallel()

	mockService, _, handler := setupConfirmHandler(t)
	ctx := context.Background()

	req := events.APIGatewayV2HTTPRequest{
		Body: `{"userId": 1, "code": "123456"}`,
	}

	mockService.On("Confirm", ctx, int64(1), "123456").
		Return(nil, errors.New("unexpected error"))

	resp, err := handler.Handle(ctx, req)

	require.NoError(t, err)
	assertErrorResponse(t, resp, 500, "internal_error")

	mockService.AssertExpectations(t)
}

func TestConfirmHandler_Handle_SessionCookieFailure(t *testing.T) {
	t.Parallel()

	mockService, mockSessionService, handler := setupConfirmHandler(t)
	ctx := context.Background()

	req := events.APIGatewayV2HTTPRequest{
		Body: `{"userId": 1, "code": "123456"}`,
	}

	expectedResult := &models.AuthenticationTokenResult{
		RefreshToken: "token",
		UserID:       1,
		Username:     "user",
	}

	mockService.On("Confirm", ctx, int64(1), "123456").Return(expectedResult, nil)
	mockSessionService.On("CreateSessionCookie", "token", int64(1), "user", req).
		Return("", errors.New("cookie creation failed"))

	resp, err := handler.Handle(ctx, req)

	require.NoError(t, err)
	assertErrorResponse(t, resp, 500, "internal_error")

	mockService.AssertExpectations(t)
	mockSessionService.AssertExpectations(t)
}

// Validation tests
func TestConfirmHandler_Handle_Validation(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name               string
		body               string
		expectedStatus     int
		expectedCode       string
		shouldCallService  bool
	}{
		{
			name:              "invalid json",
			body:              `{invalid}`,
			expectedStatus:    400,
			expectedCode:      "invalid_request",
			shouldCallService: false,
		},
		{
			name:              "missing user id",
			body:              `{"code": "123456"}`,
			expectedStatus:    400,
			expectedCode:      "missing_fields",
			shouldCallService: false,
		},
		{
			name:              "missing code",
			body:              `{"userId": 1}`,
			expectedStatus:    400,
			expectedCode:      "missing_fields",
			shouldCallService: false,
		},
		{
			name:              "zero user id",
			body:              `{"userId": 0, "code": "123456"}`,
			expectedStatus:    400,
			expectedCode:      "missing_fields",
			shouldCallService: false,
		},
		{
			name:              "empty code",
			body:              `{"userId": 1, "code": ""}`,
			expectedStatus:    400,
			expectedCode:      "missing_fields",
			shouldCallService: false,
		},
		{
			name:              "negative user id",
			body:              `{"userId": -1, "code": "123456"}`,
			expectedStatus:    400,
			expectedCode:      "missing_fields",
			shouldCallService: false,
		},
		{
			name:               "extremely long code",
			body:               fmt.Sprintf(`{"userId": 1, "code": "%s"}`, strings.Repeat("1", 1000)),
			expectedStatus:     200, // Should succeed if service accepts
			expectedCode:       "",
			shouldCallService:  true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			mockService, mockSessionService, handler := setupConfirmHandler(t)

			req := events.APIGatewayV2HTTPRequest{Body: tt.body}

			if tt.shouldCallService {
				mockService.On("Confirm", mock.Anything, mock.Anything, mock.Anything).
					Return(&models.AuthenticationTokenResult{
						RefreshToken: "token",
						UserID:       1,
						Username:     "user",
					}, nil)
				mockSessionService.On("CreateSessionCookie", mock.Anything, mock.Anything, mock.Anything, mock.Anything).
					Return("cookie", nil)
			}

			resp, err := handler.Handle(context.Background(), req)
			require.NoError(t, err)

			if tt.expectedCode != "" {
				assertErrorResponse(t, resp, tt.expectedStatus, tt.expectedCode)
			} else {
				assert.Equal(t, tt.expectedStatus, resp.StatusCode)
			}

			if tt.shouldCallService {
				mockService.AssertExpectations(t)
				mockSessionService.AssertExpectations(t)
			} else {
				mockService.AssertNotCalled(t, "Confirm")
			}
		})
	}
}

// Edge cases
func TestConfirmHandler_Handle_EdgeCases(t *testing.T) {
	t.Parallel()

	t.Run("malformed json", func(t *testing.T) {
		_, _, handler := setupConfirmHandler(t)

		req := events.APIGatewayV2HTTPRequest{Body: `{userId: 1, code: "123"}`} // Missing quotes

		resp, err := handler.Handle(context.Background(), req)
		require.NoError(t, err)
		assertErrorResponse(t, resp, 400, "invalid_request")
	})

	t.Run("unicode code", func(t *testing.T) {
		mockService, _, handler := setupConfirmHandler(t)

		unicodeCode := "123ñáéíóú"
		req := events.APIGatewayV2HTTPRequest{
			Body: fmt.Sprintf(`{"userId": 1, "code": "%s"}`, unicodeCode),
		}

		mockService.On("Confirm", mock.Anything, int64(1), unicodeCode).
			Return(nil, services.ErrInvalidConfirmationCode)

		resp, err := handler.Handle(context.Background(), req)
		require.NoError(t, err)
		assertErrorResponse(t, resp, 422, "invalid_code")
	})

	t.Run("large user id", func(t *testing.T) {
		mockService, _, handler := setupConfirmHandler(t)

		largeUserID := int64(9223372036854775807) // Max int64
		reqBody := fmt.Sprintf(`{"userId": %d, "code": "123"}`, largeUserID)
		req := events.APIGatewayV2HTTPRequest{Body: reqBody}

		mockService.On("Confirm", mock.Anything, largeUserID, "123").
			Return(nil, services.ErrUserNotFound)

		resp, err := handler.Handle(context.Background(), req)
		require.NoError(t, err)
		assertErrorResponse(t, resp, 404, "user_not_found")
	})

	t.Run("context timeout", func(t *testing.T) {
		mockService, _, handler := setupConfirmHandler(t)

		ctx, cancel := context.WithTimeout(context.Background(), time.Millisecond)
		defer cancel()
		time.Sleep(2 * time.Millisecond) // Force timeout

		req := events.APIGatewayV2HTTPRequest{Body: `{"userId": 1, "code": "123"}`}

		mockService.On("Confirm", mock.Anything, int64(1), "123").
			Return(nil, context.DeadlineExceeded)

		resp, err := handler.Handle(ctx, req)
		require.NoError(t, err)
		assertErrorResponse(t, resp, 500, "internal_error")
	})
}

// Property-based testing
func TestConfirmHandler_Handle_Idempotent(t *testing.T) {
	t.Parallel()

	mockService, mockSessionService, handler := setupConfirmHandler(t)

	ctx := context.Background()
	req := events.APIGatewayV2HTTPRequest{Body: `{"userId": 1, "code": "123"}`}

	// First call succeeds
	result := &models.AuthenticationTokenResult{
		RefreshToken: "token",
		UserID:       1,
		Username:     "user",
	}
	mockService.On("Confirm", ctx, int64(1), "123").Return(result, nil).Once()
	mockSessionService.On("CreateSessionCookie", mock.Anything, mock.Anything, mock.Anything, mock.Anything).
		Return("cookie", nil).Once()

	resp1, err := handler.Handle(ctx, req)
	require.NoError(t, err)
	assert.Equal(t, 200, resp1.StatusCode)

	// Second call should fail (user already confirmed)
	mockService.On("Confirm", ctx, int64(1), "123").Return(nil, services.ErrUserAlreadyConfirmed).Once()

	resp2, err := handler.Handle(ctx, req)
	require.NoError(t, err)
	assertErrorResponse(t, resp2, 409, "user_already_confirmed")
}
