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

func TestSignupHandler_Handle_Success(t *testing.T) {
	mockService := new(testhelpers.MockSignupService)
	handler := NewSignupHandlerWithService(mockService)

	ctx := context.Background()
	reqBody := `{"name": "John Doe", "email": "john@example.com"}`
	req := events.APIGatewayV2HTTPRequest{
		RawPath: "/auth/sign-up",
		Body:    reqBody,
		RequestContext: events.APIGatewayV2HTTPRequestContext{
			HTTP: events.APIGatewayV2HTTPRequestContextHTTPDescription{
				Method: "POST",
			},
		},
	}

	expectedUser := &models.User{
		ID:    1,
		Name:  "John Doe",
		Email: "john@example.com",
	}

	mockService.On("Signup", ctx, "John Doe", "john@example.com").Return(&models.SignupOutcome{
		User:   expectedUser,
		Status: models.SignupStatusPendingConfirmation,
	}, nil)

	resp, err := handler.Handle(ctx, req)

	require.NoError(t, err)
	assert.Equal(t, 200, resp.StatusCode)
	assert.Equal(t, "application/json", resp.Headers["Content-Type"])

	var response models.SignupResponse
	err = json.Unmarshal([]byte(resp.Body), &response)
	require.NoError(t, err)
	assert.Equal(t, expectedUser.ID, response.ID)
	assert.Equal(t, expectedUser.Name, response.Name)
	assert.Equal(t, expectedUser.Email, response.Email)
	assert.Equal(t, models.SignupStatusPendingConfirmation, response.Status)

	mockService.AssertExpectations(t)
}

func TestSignupHandler_Handle_PendingConfirmation(t *testing.T) {
	mockService := new(testhelpers.MockSignupService)
	handler := NewSignupHandlerWithService(mockService)

	ctx := context.Background()
	reqBody := `{"name": "John Doe", "email": "john@example.com"}`
	req := events.APIGatewayV2HTTPRequest{
		RawPath: "/auth/sign-up",
		Body:    reqBody,
		RequestContext: events.APIGatewayV2HTTPRequestContext{
			HTTP: events.APIGatewayV2HTTPRequestContextHTTPDescription{
				Method: "POST",
			},
		},
	}

	expectedUser := &models.User{
		ID:    1,
		Name:  "John Doe",
		Email: "john@example.com",
	}

	mockService.On("Signup", ctx, "John Doe", "john@example.com").Return(&models.SignupOutcome{
		User:   expectedUser,
		Status: models.SignupStatusPendingConfirmation,
	}, nil)

	resp, err := handler.Handle(ctx, req)

	require.NoError(t, err)
	assert.Equal(t, 200, resp.StatusCode)

	var response models.SignupResponse
	err = json.Unmarshal([]byte(resp.Body), &response)
	require.NoError(t, err)
	assert.Equal(t, expectedUser.ID, response.ID)
	assert.Equal(t, models.SignupStatusPendingConfirmation, response.Status)

	mockService.AssertExpectations(t)
}

func TestSignupHandler_Handle_InvalidJSON(t *testing.T) {
	mockService := new(testhelpers.MockSignupService)
	handler := NewSignupHandlerWithService(mockService)

	ctx := context.Background()
	req := events.APIGatewayV2HTTPRequest{
		RawPath: "/auth/sign-up",
		Body:    `{"invalid": json}`,
		RequestContext: events.APIGatewayV2HTTPRequestContext{
			HTTP: events.APIGatewayV2HTTPRequestContextHTTPDescription{
				Method: "POST",
			},
		},
	}

	resp, err := handler.Handle(ctx, req)

	require.NoError(t, err)
	assert.Equal(t, 400, resp.StatusCode)

	var errorResp models.ErrorResponse
	err = json.Unmarshal([]byte(resp.Body), &errorResp)
	require.NoError(t, err)
	assert.Equal(t, "invalid_request", errorResp.Code)
	assert.Contains(t, errorResp.Message, "Invalid request body")

	mockService.AssertNotCalled(t, "Signup")
}

func TestSignupHandler_Handle_MissingName(t *testing.T) {
	mockService := new(testhelpers.MockSignupService)
	handler := NewSignupHandlerWithService(mockService)

	ctx := context.Background()
	req := events.APIGatewayV2HTTPRequest{
		RawPath: "/auth/sign-up",
		Body:    `{"email": "john@example.com"}`,
		RequestContext: events.APIGatewayV2HTTPRequestContext{
			HTTP: events.APIGatewayV2HTTPRequestContextHTTPDescription{
				Method: "POST",
			},
		},
	}

	resp, err := handler.Handle(ctx, req)

	require.NoError(t, err)
	assert.Equal(t, 400, resp.StatusCode)

	var errorResp models.ErrorResponse
	err = json.Unmarshal([]byte(resp.Body), &errorResp)
	require.NoError(t, err)
	assert.Equal(t, "missing_fields", errorResp.Code)
	assert.Equal(t, "Name and email are required", errorResp.Message)

	mockService.AssertNotCalled(t, "Signup")
}

func TestSignupHandler_Handle_MissingEmail(t *testing.T) {
	mockService := new(testhelpers.MockSignupService)
	handler := NewSignupHandlerWithService(mockService)

	ctx := context.Background()
	req := events.APIGatewayV2HTTPRequest{
		RawPath: "/auth/sign-up",
		Body:    `{"name": "John Doe"}`,
		RequestContext: events.APIGatewayV2HTTPRequestContext{
			HTTP: events.APIGatewayV2HTTPRequestContextHTTPDescription{
				Method: "POST",
			},
		},
	}

	resp, err := handler.Handle(ctx, req)

	require.NoError(t, err)
	assert.Equal(t, 400, resp.StatusCode)

	var errorResp models.ErrorResponse
	err = json.Unmarshal([]byte(resp.Body), &errorResp)
	require.NoError(t, err)
	assert.Equal(t, "missing_fields", errorResp.Code)
	assert.Equal(t, "Name and email are required", errorResp.Message)

	mockService.AssertNotCalled(t, "Signup")
}

func TestSignupHandler_Handle_DuplicateEmail(t *testing.T) {
	mockService := new(testhelpers.MockSignupService)
	handler := NewSignupHandlerWithService(mockService)

	ctx := context.Background()
	req := events.APIGatewayV2HTTPRequest{
		RawPath: "/auth/sign-up",
		Body:    `{"name": "John Doe", "email": "existing@example.com"}`,
		RequestContext: events.APIGatewayV2HTTPRequestContext{
			HTTP: events.APIGatewayV2HTTPRequestContextHTTPDescription{
				Method: "POST",
			},
		},
	}

	mockService.On("Signup", ctx, "John Doe", "existing@example.com").
		Return(nil, services.ErrUserAlreadyExists)

	resp, err := handler.Handle(ctx, req)

	require.NoError(t, err)
	assert.Equal(t, 409, resp.StatusCode)

	var errorResp models.ErrorResponse
	err = json.Unmarshal([]byte(resp.Body), &errorResp)
	require.NoError(t, err)
	assert.Equal(t, "user_exists", errorResp.Code)
	assert.Equal(t, "User with this email already exists", errorResp.Message)

	mockService.AssertExpectations(t)
}

func TestSignupHandler_Handle_ServiceError(t *testing.T) {
	mockService := new(testhelpers.MockSignupService)
	handler := NewSignupHandlerWithService(mockService)

	ctx := context.Background()
	req := events.APIGatewayV2HTTPRequest{
		RawPath: "/auth/sign-up",
		Body:    `{"name": "John Doe", "email": "john@example.com"}`,
		RequestContext: events.APIGatewayV2HTTPRequestContext{
			HTTP: events.APIGatewayV2HTTPRequestContextHTTPDescription{
				Method: "POST",
			},
		},
	}

	mockService.On("Signup", ctx, "John Doe", "john@example.com").
		Return(nil, errors.New("internal service error"))

	resp, err := handler.Handle(ctx, req)

	require.NoError(t, err)
	assert.Equal(t, 500, resp.StatusCode)

	var errorResp models.ErrorResponse
	err = json.Unmarshal([]byte(resp.Body), &errorResp)
	require.NoError(t, err)
	assert.Equal(t, "internal_error", errorResp.Code)
	assert.Contains(t, errorResp.Message, "Internal server error")

	mockService.AssertExpectations(t)
}

func TestSignupHandler_Handle_EmptyBody(t *testing.T) {
	mockService := new(testhelpers.MockSignupService)
	handler := NewSignupHandlerWithService(mockService)

	ctx := context.Background()
	req := events.APIGatewayV2HTTPRequest{
		RawPath: "/auth/sign-up",
		Body:    "",
		RequestContext: events.APIGatewayV2HTTPRequestContext{
			HTTP: events.APIGatewayV2HTTPRequestContextHTTPDescription{
				Method: "POST",
			},
		},
	}

	resp, err := handler.Handle(ctx, req)

	require.NoError(t, err)
	assert.Equal(t, 400, resp.StatusCode)

	var errorResp models.ErrorResponse
	err = json.Unmarshal([]byte(resp.Body), &errorResp)
	require.NoError(t, err)
	assert.Equal(t, "invalid_request", errorResp.Code)

	mockService.AssertNotCalled(t, "Signup")
}

func TestErrorResponse(t *testing.T) {
	resp := errorResponse(404, "not_found", "Not found")

	assert.Equal(t, 404, resp.StatusCode)
	assert.Equal(t, "application/json", resp.Headers["Content-Type"])

	var errorResp models.ErrorResponse
	err := json.Unmarshal([]byte(resp.Body), &errorResp)
	require.NoError(t, err)
	assert.Equal(t, "not_found", errorResp.Code)
	assert.Equal(t, "Not found", errorResp.Message)
}

// Helper function to create handler with mock service for testing.
func NewSignupHandlerWithService(service testhelpers.SignupServiceInterface) *SignupHandler {
	return NewSignupHandlerWithInterface(service)
}
