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
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
)

func TestRefreshHandler_Handle(t *testing.T) {
	tests := []struct {
		name           string
		setupRequest   func() events.APIGatewayV2HTTPRequest
		setupMock      func(*testhelpers.MockSessionService)
		expectedStatus int
		expectedCode   string
		validateBody   func(t *testing.T, body string, statusCode int)
		assertMocks    func(t *testing.T, mockSessionService *testhelpers.MockSessionService)
	}{
		{
			name: "Success with single session cookie",
			setupRequest: func() events.APIGatewayV2HTTPRequest {
				return events.APIGatewayV2HTTPRequest{
					Cookies: []string{"session_id=encrypted-session-data"},
				}
			},
			setupMock: func(mockSessionService *testhelpers.MockSessionService) {
				expectedResponse := &models.AccessTokenResponse{
					AccessToken: "new-access-token",
					ExpiresIn:   3600,
				}
				mockSessionService.On("RefreshAccessToken", mock.Anything, "encrypted-session-data").
					Return(expectedResponse, nil).Once()
			},
			expectedStatus: 200,
			validateBody: func(t *testing.T, body string, statusCode int) {
				var response models.AccessTokenResponse
				err := json.Unmarshal([]byte(body), &response)
				require.NoError(t, err)
				assert.Equal(t, "new-access-token", response.AccessToken)
				assert.Equal(t, int32(3600), response.ExpiresIn)
			},
			assertMocks: func(t *testing.T, mockSessionService *testhelpers.MockSessionService) {
				mockSessionService.AssertExpectations(t)
			},
		},
		{
			name: "Success with multiple cookies (session_id first)",
			setupRequest: func() events.APIGatewayV2HTTPRequest {
				return events.APIGatewayV2HTTPRequest{
					Cookies: []string{"other=value", "session_id=encrypted-session-data", "another=test"},
				}
			},
			setupMock: func(mockSessionService *testhelpers.MockSessionService) {
				expectedResponse := &models.AccessTokenResponse{
					AccessToken: "new-access-token",
					ExpiresIn:   3600,
				}
				mockSessionService.On("RefreshAccessToken", mock.Anything, "encrypted-session-data").
					Return(expectedResponse, nil).Once()
			},
			expectedStatus: 200,
			validateBody: func(t *testing.T, body string, statusCode int) {
				var response models.AccessTokenResponse
				err := json.Unmarshal([]byte(body), &response)
				require.NoError(t, err)
				assert.Equal(t, "new-access-token", response.AccessToken)
			},
			assertMocks: func(t *testing.T, mockSessionService *testhelpers.MockSessionService) {
				mockSessionService.AssertExpectations(t)
			},
		},
		{
			name: "Success with multiple cookies (session_id last)",
			setupRequest: func() events.APIGatewayV2HTTPRequest {
				return events.APIGatewayV2HTTPRequest{
					Cookies: []string{"other=value", "another=test", "session_id=encrypted-session-data"},
				}
			},
			setupMock: func(mockSessionService *testhelpers.MockSessionService) {
				expectedResponse := &models.AccessTokenResponse{
					AccessToken: "new-access-token",
					ExpiresIn:   3600,
				}
				mockSessionService.On("RefreshAccessToken", mock.Anything, "encrypted-session-data").
					Return(expectedResponse, nil).Once()
			},
			expectedStatus: 200,
			validateBody: func(t *testing.T, body string, statusCode int) {
				var response models.AccessTokenResponse
				err := json.Unmarshal([]byte(body), &response)
				require.NoError(t, err)
				assert.Equal(t, "new-access-token", response.AccessToken)
			},
			assertMocks: func(t *testing.T, mockSessionService *testhelpers.MockSessionService) {
				mockSessionService.AssertExpectations(t)
			},
		},
		{
			name: "Missing cookie",
			setupRequest: func() events.APIGatewayV2HTTPRequest {
				return events.APIGatewayV2HTTPRequest{
					Cookies: []string{},
				}
			},
			setupMock: func(mockSessionService *testhelpers.MockSessionService) {
				// No mock setup needed
			},
			expectedStatus: 401,
			expectedCode:   "unauthorized",
			validateBody: func(t *testing.T, body string, statusCode int) {
				var response models.ErrorResponse
				err := json.Unmarshal([]byte(body), &response)
				require.NoError(t, err)
				assert.Equal(t, "unauthorized", response.Code)
				assert.Equal(t, "Missing session cookie", response.Message)
			},
			assertMocks: func(t *testing.T, mockSessionService *testhelpers.MockSessionService) {
				mockSessionService.AssertNotCalled(t, "RefreshAccessToken", mock.Anything, mock.Anything)
			},
		},
		{
			name: "Cookie without session_id",
			setupRequest: func() events.APIGatewayV2HTTPRequest {
				return events.APIGatewayV2HTTPRequest{
					Cookies: []string{"other=value", "another=test"},
				}
			},
			setupMock: func(mockSessionService *testhelpers.MockSessionService) {
				// No mock setup needed
			},
			expectedStatus: 401,
			expectedCode:   "unauthorized",
			validateBody: func(t *testing.T, body string, statusCode int) {
				var response models.ErrorResponse
				err := json.Unmarshal([]byte(body), &response)
				require.NoError(t, err)
				assert.Equal(t, "unauthorized", response.Code)
				assert.Equal(t, "Missing session cookie", response.Message)
			},
			assertMocks: func(t *testing.T, mockSessionService *testhelpers.MockSessionService) {
				mockSessionService.AssertNotCalled(t, "RefreshAccessToken", mock.Anything, mock.Anything)
			},
		},
		{
			name: "Malformed cookie (no equals sign)",
			setupRequest: func() events.APIGatewayV2HTTPRequest {
				return events.APIGatewayV2HTTPRequest{
					Cookies: []string{"session_id"},
				}
			},
			setupMock: func(mockSessionService *testhelpers.MockSessionService) {
				// No mock setup needed
			},
			expectedStatus: 401,
			expectedCode:   "unauthorized",
			validateBody: func(t *testing.T, body string, statusCode int) {
				var response models.ErrorResponse
				err := json.Unmarshal([]byte(body), &response)
				require.NoError(t, err)
				assert.Equal(t, "unauthorized", response.Code)
				assert.Equal(t, "Missing session cookie", response.Message)
			},
			assertMocks: func(t *testing.T, mockSessionService *testhelpers.MockSessionService) {
				mockSessionService.AssertNotCalled(t, "RefreshAccessToken", mock.Anything, mock.Anything)
			},
		},
		{
			name: "Invalid session",
			setupRequest: func() events.APIGatewayV2HTTPRequest {
				return events.APIGatewayV2HTTPRequest{
					Cookies: []string{"session_id=invalid-session"},
				}
			},
			setupMock: func(mockSessionService *testhelpers.MockSessionService) {
				mockSessionService.On("RefreshAccessToken", mock.Anything, "invalid-session").
					Return(nil, services.ErrInvalidSession).Once()
			},
			expectedStatus: 401,
			expectedCode:   "invalid_session",
			validateBody: func(t *testing.T, body string, statusCode int) {
				var response models.ErrorResponse
				err := json.Unmarshal([]byte(body), &response)
				require.NoError(t, err)
				assert.Equal(t, "invalid_session", response.Code)
				assert.Equal(t, "Invalid session", response.Message)
			},
			assertMocks: func(t *testing.T, mockSessionService *testhelpers.MockSessionService) {
				mockSessionService.AssertExpectations(t)
			},
		},
		{
			name: "User not confirmed",
			setupRequest: func() events.APIGatewayV2HTTPRequest {
				return events.APIGatewayV2HTTPRequest{
					Cookies: []string{"session_id=unconfirmed-session"},
				}
			},
			setupMock: func(mockSessionService *testhelpers.MockSessionService) {
				mockSessionService.On("RefreshAccessToken", mock.Anything, "unconfirmed-session").
					Return(nil, services.ErrUserNotConfirmed).Once()
			},
			expectedStatus: 403,
			expectedCode:   "user_not_confirmed",
			validateBody: func(t *testing.T, body string, statusCode int) {
				var response models.ErrorResponse
				err := json.Unmarshal([]byte(body), &response)
				require.NoError(t, err)
				assert.Equal(t, "user_not_confirmed", response.Code)
				assert.Equal(t, "User not confirmed", response.Message)
			},
			assertMocks: func(t *testing.T, mockSessionService *testhelpers.MockSessionService) {
				mockSessionService.AssertExpectations(t)
			},
		},
		{
			name: "Refresh token failed",
			setupRequest: func() events.APIGatewayV2HTTPRequest {
				return events.APIGatewayV2HTTPRequest{
					Cookies: []string{"session_id=expired-session"},
				}
			},
			setupMock: func(mockSessionService *testhelpers.MockSessionService) {
				mockSessionService.On("RefreshAccessToken", mock.Anything, "expired-session").
					Return(nil, services.ErrRefreshTokenFailed).Once()
			},
			expectedStatus: 401,
			expectedCode:   "refresh_failed",
			validateBody: func(t *testing.T, body string, statusCode int) {
				var response models.ErrorResponse
				err := json.Unmarshal([]byte(body), &response)
				require.NoError(t, err)
				assert.Equal(t, "refresh_failed", response.Code)
				assert.Equal(t, "Failed to refresh token", response.Message)
			},
			assertMocks: func(t *testing.T, mockSessionService *testhelpers.MockSessionService) {
				mockSessionService.AssertExpectations(t)
			},
		},
		{
			name: "Internal error",
			setupRequest: func() events.APIGatewayV2HTTPRequest {
				return events.APIGatewayV2HTTPRequest{
					Cookies: []string{"session_id=error-session"},
				}
			},
			setupMock: func(mockSessionService *testhelpers.MockSessionService) {
				mockSessionService.On("RefreshAccessToken", mock.Anything, "error-session").
					Return(nil, errors.New("unexpected error")).Once()
			},
			expectedStatus: 500,
			expectedCode:   "internal_error",
			validateBody: func(t *testing.T, body string, statusCode int) {
				var response models.ErrorResponse
				err := json.Unmarshal([]byte(body), &response)
				require.NoError(t, err)
				assert.Equal(t, "internal_error", response.Code)
				assert.Equal(t, "Internal server error", response.Message)
			},
			assertMocks: func(t *testing.T, mockSessionService *testhelpers.MockSessionService) {
				mockSessionService.AssertExpectations(t)
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			mockSessionService := new(testhelpers.MockSessionService)
			handler := NewRefreshHandlerWithInterface(mockSessionService)

			ctx := context.Background()
			req := tt.setupRequest()
			tt.setupMock(mockSessionService)

			resp, err := handler.Handle(ctx, req)

			require.NoError(t, err)
			assert.Equal(t, tt.expectedStatus, resp.StatusCode)

			// Validate headers
			assert.Equal(t, "application/json", resp.Headers["Content-Type"])

			// Validate body structure
			assert.NotEmpty(t, resp.Body)
			tt.validateBody(t, resp.Body, resp.StatusCode)

			// Assert mock expectations
			tt.assertMocks(t, mockSessionService)
		})
	}
}

func TestRefreshHandler_Handle_ContextCancellation(t *testing.T) {
	mockSessionService := new(testhelpers.MockSessionService)
	handler := NewRefreshHandlerWithInterface(mockSessionService)

	ctx, cancel := context.WithCancel(context.Background())
	cancel() // Cancel immediately

	req := events.APIGatewayV2HTTPRequest{
		Cookies: []string{"session_id=test-session"},
	}

	// Mock should be called but context is cancelled
	mockSessionService.On("RefreshAccessToken", mock.Anything, "test-session").
		Return(&models.AccessTokenResponse{}, nil).Once()

	resp, err := handler.Handle(ctx, req)

	// Handler should still return a response even with cancelled context
	require.NoError(t, err)
	// The exact behavior depends on if the service checks context, but we test that handler doesn't crash
	assert.NotNil(t, resp)
	mockSessionService.AssertExpectations(t)
}

func TestRefreshHandler_Handle_JSONMarshalingError(t *testing.T) {
	mockSessionService := new(testhelpers.MockSessionService)

	// Create a marshaling function that always fails
	failingMarshal := func(v interface{}) ([]byte, error) {
		return nil, errors.New("marshaling failed")
	}

	handler := NewRefreshHandlerWithMarshaler(mockSessionService, failingMarshal)

	ctx := context.Background()

	// Mock successful session refresh
	mockSessionService.On("RefreshAccessToken", ctx, "encrypted_session_data").Return(&models.AccessTokenResponse{
		AccessToken: "new_token",
		ExpiresIn:   3600,
	}, nil).Once()

	req := events.APIGatewayV2HTTPRequest{
		RequestContext: events.APIGatewayV2HTTPRequestContext{
			HTTP: events.APIGatewayV2HTTPRequestContextHTTPDescription{
				Method: "POST",
			},
		},
		Cookies: []string{"session_id=encrypted_session_data"},
	}

	resp, err := handler.Handle(ctx, req)

	assert.NoError(t, err)
	assert.Equal(t, 500, resp.StatusCode)

	var errorResp models.ErrorResponse
	err = json.Unmarshal([]byte(resp.Body), &errorResp)
	assert.NoError(t, err)
	assert.Equal(t, "internal_error", errorResp.Code)
	assert.Equal(t, "Failed to marshal response", errorResp.Message)

	mockSessionService.AssertExpectations(t)
}

// Benchmark test to ensure performance
func BenchmarkRefreshHandler_Handle_Success(b *testing.B) {
	mockSessionService := new(testhelpers.MockSessionService)
	handler := NewRefreshHandlerWithInterface(mockSessionService)

	ctx := context.Background()
	req := events.APIGatewayV2HTTPRequest{
		Cookies: []string{"session_id=encrypted-session-data"},
	}

	expectedResponse := &models.AccessTokenResponse{
		AccessToken: "new-access-token",
		ExpiresIn:   3600,
	}

	mockSessionService.On("RefreshAccessToken", mock.Anything, "encrypted-session-data").
		Return(expectedResponse, nil)

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		_, _ = handler.Handle(ctx, req)
	}
}
