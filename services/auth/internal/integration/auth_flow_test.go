package integration

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"testing"
	"time"

	"services/auth/internal/cognito"
	"services/auth/internal/encryption"
	"services/auth/internal/handlers"
	"services/auth/internal/jwt"
	"services/auth/internal/models"
	"services/auth/internal/repositories"
	"services/auth/internal/services"

	"github.com/aws/aws-lambda-go/events"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestAuthFlow_Integration_FullCycle(t *testing.T) {
	if testing.Short() {
		t.Skip("Skipping integration test in short mode")
	}

	// 1. Setup Environment
	setup := setupIntegrationTest(t)
	defer setup.Cleanup()

	cfg := setup.Cfg

	// Cognito Client
	cognitoClient, err := cognito.NewClient(cfg)
	if err != nil {
		t.Skipf("Skipping integration test - Cognito client setup failed: %v", err)
	}

	// Repositories & Services
	userRepo := repositories.NewUserRepository(setup.Pool)
	signupService := services.NewSignupService(userRepo, cognitoClient, cfg.EncryptionSecret)
	sessionService := services.NewSessionService(userRepo, cognitoClient, cfg.EncryptionSecret)

	// JWT Validator
	// Ensure validator uses the local JWKS endpoint
	validator := jwt.NewValidator(cfg)
	// Force fetch keys immediately to ensure connectivity
	// (ValidateToken does this lazily, but good to know if it fails early)

	// Handlers
	confirmHandler := handlers.NewConfirmHandlerWithInterface(signupService, sessionService)
	refreshHandler := handlers.NewRefreshHandlerWithInterface(sessionService)
	meHandler := handlers.NewMeHandlerWithInterface(userRepo, cognitoClient, validator)

	ctx := context.Background()
	name := "Auth Flow User"
	email := fmt.Sprintf("auth-flow-%d@example.com", time.Now().UnixNano())

	// 2. Signup
	t.Logf("Starting Signup for %s", email)
	signupResult, err := signupService.Signup(ctx, name, email)
	if err != nil {
		if errors.Is(err, services.ErrSignupProviderUnavailable) {
			t.Skipf("Skipping integration test - signup provider not available: %v", err)
			return
		}
		require.NoError(t, err, "Signup should succeed")
	}
	require.NotNil(t, signupResult)
	userID := signupResult.User.ID

	// Decrypt password for confirmation (simulating user knowing their temp password)
	decryptedPassword, err := encryption.Decrypt(*signupResult.User.TemporaryPassword, cfg.EncryptionSecret)
	require.NoError(t, err)
	require.NotEmpty(t, decryptedPassword)

	// Wait for Cognito eventual consistency
	time.Sleep(1 * time.Second)

	// 3. Confirm (Login)
	t.Log("Confirming User")
	confirmationCode := "123123" // Default cognito-local code
	reqBody := fmt.Sprintf(`{"userId": %d, "code": "%s"}`, userID, confirmationCode)
	confirmReq := events.APIGatewayV2HTTPRequest{
		Body: reqBody,
	}

	confirmResp, err := confirmHandler.Handle(ctx, confirmReq)
	require.NoError(t, err)
	require.Equal(t, 200, confirmResp.StatusCode, "Confirm should succeed: %s", confirmResp.Body)

	// Extract Session Cookie
	cookieHeader := confirmResp.Headers["Set-Cookie"]
	sessionID := extractSessionID(cookieHeader)
	require.NotEmpty(t, sessionID, "Session ID must be present in Set-Cookie")

	// 4. Refresh (Get Access Token)
	t.Log("Refreshing Token (1st time)")
	refreshReq := events.APIGatewayV2HTTPRequest{
		Cookies: []string{"session_id=" + sessionID},
	}

	refreshResp, err := refreshHandler.Handle(ctx, refreshReq)
	require.NoError(t, err)
	require.Equal(t, 200, refreshResp.StatusCode, "Refresh should succeed: %s", refreshResp.Body)

	var tokenResp models.AccessTokenResponse
	err = json.Unmarshal([]byte(refreshResp.Body), &tokenResp)
	require.NoError(t, err)
	accessToken := tokenResp.AccessToken
	require.NotEmpty(t, accessToken, "Access Token must be returned")

	// 5. Me (Get User Info)
	t.Log("Calling Me Handler")
	meReq := events.APIGatewayV2HTTPRequest{
		Headers: map[string]string{
			"Authorization": "Bearer " + accessToken,
		},
	}

	meResp, err := meHandler.Handle(ctx, meReq)
	require.NoError(t, err)
	require.Equal(t, 200, meResp.StatusCode, "Me endpoint should succeed: %s", meResp.Body)

	var userInfo models.UserInfoResponse
	err = json.Unmarshal([]byte(meResp.Body), &userInfo)
	require.NoError(t, err)
	assert.Equal(t, userID, userInfo.ID)
	assert.Equal(t, name, userInfo.Name)

	// 6. Refresh Again (Verify session persistence)
	t.Log("Refreshing Token (2nd time)")
	refreshResp2, err := refreshHandler.Handle(ctx, refreshReq)
	require.NoError(t, err)
	require.Equal(t, 200, refreshResp2.StatusCode)

	var tokenResp2 models.AccessTokenResponse
	err = json.Unmarshal([]byte(refreshResp2.Body), &tokenResp2)
	require.NoError(t, err)
	accessToken2 := tokenResp2.AccessToken
	require.NotEmpty(t, accessToken2)

	// 7. Me with New Token
	t.Log("Calling Me Handler with New Token")
	meReq2 := events.APIGatewayV2HTTPRequest{
		Headers: map[string]string{
			"Authorization": "Bearer " + accessToken2,
		},
	}
	meResp2, err := meHandler.Handle(ctx, meReq2)
	require.NoError(t, err)
	assert.Equal(t, 200, meResp2.StatusCode)
}

func TestAuth_Integration_SessionExpiry(t *testing.T) {
	if testing.Short() {
		t.Skip("Skipping integration test in short mode")
	}

	// 1. Setup Environment
	setup := setupIntegrationTest(t)
	defer setup.Cleanup()

	cfg := setup.Cfg

	// Cognito Client
	cognitoClient, err := cognito.NewClient(cfg)
	if err != nil {
		t.Skipf("Skipping integration test - Cognito client setup failed: %v", err)
	}

	// Repositories & Services
	userRepo := repositories.NewUserRepository(setup.Pool)
	signupService := services.NewSignupService(userRepo, cognitoClient, cfg.EncryptionSecret)
	sessionService := services.NewSessionService(userRepo, cognitoClient, cfg.EncryptionSecret)

	// Handlers
	confirmHandler := handlers.NewConfirmHandlerWithInterface(signupService, sessionService)
	refreshHandler := handlers.NewRefreshHandlerWithInterface(sessionService)

	ctx := context.Background()
	name := "Session Expiry Test User"
	email := fmt.Sprintf("session-expiry-%d@example.com", time.Now().UnixNano())

	// 2. Signup
	t.Logf("Starting Signup for %s", email)
	signupResult, err := signupService.Signup(ctx, name, email)
	if err != nil {
		if errors.Is(err, services.ErrSignupProviderUnavailable) {
			t.Skipf("Skipping integration test - signup provider not available: %v", err)
			return
		}
		require.NoError(t, err, "Signup should succeed")
	}
	require.NotNil(t, signupResult)
	userID := signupResult.User.ID

	// Wait for Cognito eventual consistency
	time.Sleep(1 * time.Second)

	// 3. Confirm (Login)
	t.Log("Confirming User")
	confirmationCode := "123123" // Default cognito-local code
	reqBody := fmt.Sprintf(`{"userId": %d, "code": "%s"}`, userID, confirmationCode)
	confirmReq := events.APIGatewayV2HTTPRequest{
		Body: reqBody,
	}

	confirmResp, err := confirmHandler.Handle(ctx, confirmReq)
	require.NoError(t, err)
	require.Equal(t, 200, confirmResp.StatusCode, "Confirm should succeed: %s", confirmResp.Body)

	// Extract Session Cookie
	cookieHeader := confirmResp.Headers["Set-Cookie"]
	sessionID := extractSessionID(cookieHeader)
	require.NotEmpty(t, sessionID, "Session ID must be present in Set-Cookie")

	// 4. Refresh (Get Access Token)
	t.Log("Refreshing Token (1st time)")
	refreshReq := events.APIGatewayV2HTTPRequest{
		Cookies: []string{"session_id=" + sessionID},
	}

	refreshResp, err := refreshHandler.Handle(ctx, refreshReq)
	require.NoError(t, err)
	require.Equal(t, 200, refreshResp.StatusCode, "Refresh should succeed: %s", refreshResp.Body)

	var tokenResp models.AccessTokenResponse
	err = json.Unmarshal([]byte(refreshResp.Body), &tokenResp)
	require.NoError(t, err)
	accessToken := tokenResp.AccessToken
	require.NotEmpty(t, accessToken, "Access Token must be returned")

	// 5. Try to refresh with invalid session (should fail)
	t.Log("Attempting refresh with invalid session")
	invalidRefreshReq := events.APIGatewayV2HTTPRequest{
		Cookies: []string{"session_id=invalid-session-data"},
	}

	invalidRefreshResp, err := refreshHandler.Handle(ctx, invalidRefreshReq)
	require.NoError(t, err)
	assert.Equal(t, 401, invalidRefreshResp.StatusCode, "Refresh should fail with invalid session")

	var errorResp models.ErrorResponse
	err = json.Unmarshal([]byte(invalidRefreshResp.Body), &errorResp)
	require.NoError(t, err)
	assert.Equal(t, "invalid_session", errorResp.Code, "Should return invalid_session error")
}
