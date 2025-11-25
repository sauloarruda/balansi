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
	t.Run("Success", func(t *testing.T) {
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

		mockSessionService.On("RefreshAccessToken", ctx, "encrypted-session-data").
			Return(expectedResponse, nil)

		resp, err := handler.Handle(ctx, req)

		require.NoError(t, err)
		assert.Equal(t, 200, resp.StatusCode)

		var body models.AccessTokenResponse
		err = json.Unmarshal([]byte(resp.Body), &body)
		require.NoError(t, err)
		assert.Equal(t, "new-access-token", body.AccessToken)
		assert.Equal(t, int32(3600), body.ExpiresIn)
	})

	t.Run("Missing Cookie", func(t *testing.T) {
		mockSessionService := new(testhelpers.MockSessionService)
		handler := NewRefreshHandlerWithInterface(mockSessionService)

		req := events.APIGatewayV2HTTPRequest{
			Cookies: []string{},
		}

		resp, err := handler.Handle(context.Background(), req)

		require.NoError(t, err)
		assert.Equal(t, 401, resp.StatusCode)

		var body map[string]interface{}
		json.Unmarshal([]byte(resp.Body), &body)
		assert.Equal(t, "unauthorized", body["code"])
	})

	t.Run("Invalid Session", func(t *testing.T) {
		mockSessionService := new(testhelpers.MockSessionService)
		handler := NewRefreshHandlerWithInterface(mockSessionService)

		req := events.APIGatewayV2HTTPRequest{
			Cookies: []string{"session_id=invalid-session"},
		}

		mockSessionService.On("RefreshAccessToken", mock.Anything, "invalid-session").
			Return(nil, services.ErrInvalidSession)

		resp, err := handler.Handle(context.Background(), req)

		require.NoError(t, err)
		assert.Equal(t, 401, resp.StatusCode)

		var body map[string]interface{}
		json.Unmarshal([]byte(resp.Body), &body)
		assert.Equal(t, "invalid_session", body["code"])
	})

	t.Run("User Not Confirmed", func(t *testing.T) {
		mockSessionService := new(testhelpers.MockSessionService)
		handler := NewRefreshHandlerWithInterface(mockSessionService)

		req := events.APIGatewayV2HTTPRequest{
			Cookies: []string{"session_id=unconfirmed-session"},
		}

		mockSessionService.On("RefreshAccessToken", mock.Anything, "unconfirmed-session").
			Return(nil, services.ErrUserNotConfirmed)

		resp, err := handler.Handle(context.Background(), req)

		require.NoError(t, err)
		assert.Equal(t, 403, resp.StatusCode)

		var body map[string]interface{}
		json.Unmarshal([]byte(resp.Body), &body)
		assert.Equal(t, "user_not_confirmed", body["code"])
	})

	t.Run("Refresh Token Failed", func(t *testing.T) {
		mockSessionService := new(testhelpers.MockSessionService)
		handler := NewRefreshHandlerWithInterface(mockSessionService)

		req := events.APIGatewayV2HTTPRequest{
			Cookies: []string{"session_id=expired-session"},
		}

		mockSessionService.On("RefreshAccessToken", mock.Anything, "expired-session").
			Return(nil, services.ErrRefreshTokenFailed)

		resp, err := handler.Handle(context.Background(), req)

		require.NoError(t, err)
		assert.Equal(t, 401, resp.StatusCode)

		var body map[string]interface{}
		json.Unmarshal([]byte(resp.Body), &body)
		assert.Equal(t, "refresh_failed", body["code"])
	})

	t.Run("Internal Error", func(t *testing.T) {
		mockSessionService := new(testhelpers.MockSessionService)
		handler := NewRefreshHandlerWithInterface(mockSessionService)

		req := events.APIGatewayV2HTTPRequest{
			Cookies: []string{"session_id=error-session"},
		}

		mockSessionService.On("RefreshAccessToken", mock.Anything, "error-session").
			Return(nil, errors.New("unexpected error"))

		resp, err := handler.Handle(context.Background(), req)

		require.NoError(t, err)
		assert.Equal(t, 500, resp.StatusCode)

		var body map[string]interface{}
		json.Unmarshal([]byte(resp.Body), &body)
		assert.Equal(t, "internal_error", body["code"])
	})
}
