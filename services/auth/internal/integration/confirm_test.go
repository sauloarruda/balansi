package integration

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"testing"
	"time"

	"services/auth/internal/cognito"
	"services/auth/internal/handlers"
	"services/auth/internal/models"
	"services/auth/internal/repositories"
	"services/auth/internal/services"

	"github.com/aws/aws-lambda-go/events"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)


func TestConfirm_Integration_Success(t *testing.T) {
	if testing.Short() {
		t.Skip("Skipping integration test in short mode")
	}

	// Setup test database and config
	setup := setupIntegrationTest(t)
	defer setup.Cleanup()

	cfg := setup.Cfg

	// Setup Cognito client (using cognito-local if available)

	cognitoClient, err := cognito.NewClient(cfg)
	if err != nil {
		t.Skipf("Skipping integration test - Cognito client setup failed: %v", err)
	}

	// Initialize dependencies
	userRepo := repositories.NewUserRepository(setup.Pool)
	signupService := services.NewSignupService(userRepo, cognitoClient, cfg.EncryptionSecret)
	sessionService := services.NewSessionService(userRepo, cognitoClient, cfg.EncryptionSecret)
	confirmHandler := handlers.NewConfirmHandlerWithInterface(signupService, sessionService)

	ctx := context.Background()
	name := "Confirm Integration Test User"
	email := fmt.Sprintf("confirm-integration-%d@example.com", time.Now().UnixNano())

	// Step 1: Signup a new user
	signupResult, err := signupService.Signup(ctx, name, email)
	if err != nil {
		if errors.Is(err, services.ErrSignupProviderUnavailable) {
			t.Skipf("Skipping integration test - signup provider not available: %v", err)
			return
		}
		require.NoError(t, err, "Signup should succeed")
	}

	require.NotNil(t, signupResult)
	require.NotNil(t, signupResult.User)
	assert.Equal(t, models.SignupStatusPendingConfirmation, signupResult.Status)
	userID := signupResult.User.ID

	// Step 2: Wait a bit for Cognito to process the signup
	time.Sleep(500 * time.Millisecond)

	// Step 3: Call confirm handler with cognito-local's default code
	confirmationCode := "123123"
	reqBody := fmt.Sprintf(`{"userId": %d, "code": "%s"}`, userID, confirmationCode)
	req := events.APIGatewayV2HTTPRequest{
		Body: reqBody,
	}

	resp, err := confirmHandler.Handle(ctx, req)
	require.NoError(t, err)

	// Step 4: Verify response - must succeed
	require.Equal(t, 200, resp.StatusCode, "Expected success but got status %d: %s", resp.StatusCode, resp.Body)
	assert.Equal(t, "application/json", resp.Headers["Content-Type"])

	// Verify cookie is set
	assert.Contains(t, resp.Headers["Set-Cookie"], "session_id=", "Session cookie should be set")
	assert.Contains(t, resp.Headers["Set-Cookie"], "HttpOnly", "Session cookie should be HttpOnly")
	assert.Contains(t, resp.Headers["Set-Cookie"], "SameSite=Lax", "Session cookie should have SameSite=Lax")

	// Verify response body
	var successResp map[string]interface{}
	err = json.Unmarshal([]byte(resp.Body), &successResp)
	require.NoError(t, err)
	assert.Equal(t, true, successResp["success"], "Response should indicate success")

	// Verify user status was updated in database
	confirmedUser, err := userRepo.FindByID(ctx, userID)
	require.NoError(t, err)
	require.NotNil(t, confirmedUser)
	assert.Equal(t, models.UserStatusConfirmed, confirmedUser.Status, "User status should be confirmed")
}

func TestConfirm_Integration_UserNotFound(t *testing.T) {
	if testing.Short() {
		t.Skip("Skipping integration test in short mode")
	}

	// Setup test database and config
	setup := setupIntegrationTest(t)
	defer setup.Cleanup()

	cfg := setup.Cfg

	cognitoClient, err := cognito.NewClient(cfg)
	if err != nil {
		t.Skipf("Skipping integration test - Cognito client setup failed: %v", err)
	}

	userRepo := repositories.NewUserRepository(setup.Pool)
	signupService := services.NewSignupService(userRepo, cognitoClient, cfg.EncryptionSecret)
	sessionService := services.NewSessionService(userRepo, cognitoClient, cfg.EncryptionSecret)
	confirmHandler := handlers.NewConfirmHandlerWithInterface(signupService, sessionService)

	ctx := context.Background()

	// Try to confirm with non-existent user ID
	reqBody := `{"userId": 99999, "code": "123456"}`
	req := events.APIGatewayV2HTTPRequest{
		Body: reqBody,
	}

	resp, err := confirmHandler.Handle(ctx, req)
	require.NoError(t, err)
	assert.Equal(t, 404, resp.StatusCode)

	var errorResp models.ErrorResponse
	err = json.Unmarshal([]byte(resp.Body), &errorResp)
	require.NoError(t, err)
	assert.Equal(t, "user_not_found", errorResp.Code)
	assert.Equal(t, "User not found", errorResp.Message)
}

func TestConfirm_Integration_InvalidCode(t *testing.T) {
	if testing.Short() {
		t.Skip("Skipping integration test in short mode")
	}

	// Setup test database and config
	setup := setupIntegrationTest(t)
	defer setup.Cleanup()

	cfg := setup.Cfg

	cognitoClient, err := cognito.NewClient(cfg)
	if err != nil {
		t.Skipf("Skipping integration test - Cognito client setup failed: %v", err)
	}

	userRepo := repositories.NewUserRepository(setup.Pool)
	signupService := services.NewSignupService(userRepo, cognitoClient, cfg.EncryptionSecret)
	sessionService := services.NewSessionService(userRepo, cognitoClient, cfg.EncryptionSecret)
	confirmHandler := handlers.NewConfirmHandlerWithInterface(signupService, sessionService)

	ctx := context.Background()
	name := "Invalid Code Test User"
	email := fmt.Sprintf("invalid-code-%d@example.com", time.Now().UnixNano())

	// Step 1: Signup a new user
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

	// Wait a bit for Cognito to process
	time.Sleep(500 * time.Millisecond)

	// Step 2: Try to confirm with wrong code
	reqBody := fmt.Sprintf(`{"userId": %d, "code": "wrong-code"}`, userID)
	req := events.APIGatewayV2HTTPRequest{
		Body: reqBody,
	}

	resp, err := confirmHandler.Handle(ctx, req)
	require.NoError(t, err)
	assert.Equal(t, 422, resp.StatusCode)

	var errorResp models.ErrorResponse
	err = json.Unmarshal([]byte(resp.Body), &errorResp)
	require.NoError(t, err)
	assert.True(t, errorResp.Code == "invalid_code" || errorResp.Code == "expired_code",
		"Expected invalid_code or expired_code, got: %s", errorResp.Code)
}

func TestConfirm_Integration_AlreadyConfirmed(t *testing.T) {
	if testing.Short() {
		t.Skip("Skipping integration test in short mode")
	}

	// Setup test database and config
	setup := setupIntegrationTest(t)
	defer setup.Cleanup()

	cfg := setup.Cfg

	cognitoClient, err := cognito.NewClient(cfg)
	if err != nil {
		t.Skipf("Skipping integration test - Cognito client setup failed: %v", err)
	}

	userRepo := repositories.NewUserRepository(setup.Pool)
	signupService := services.NewSignupService(userRepo, cognitoClient, cfg.EncryptionSecret)
	sessionService := services.NewSessionService(userRepo, cognitoClient, cfg.EncryptionSecret)
	confirmHandler := handlers.NewConfirmHandlerWithInterface(signupService, sessionService)

	ctx := context.Background()
	name := "Already Confirmed Test User"
	email := fmt.Sprintf("already-confirmed-%d@example.com", time.Now().UnixNano())

	// Step 1: Signup a new user
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

	// Wait a bit for Cognito to process
	time.Sleep(500 * time.Millisecond)

	// Step 2: Confirm the user first time with cognito-local's default code
	confirmationCode := "123123"
	reqBody1 := fmt.Sprintf(`{"userId": %d, "code": "%s"}`, userID, confirmationCode)
	req1 := events.APIGatewayV2HTTPRequest{
		Body: reqBody1,
	}

	resp1, err := confirmHandler.Handle(ctx, req1)
	require.NoError(t, err)
	require.Equal(t, 200, resp1.StatusCode, "First confirmation should succeed: %s", resp1.Body)

	time.Sleep(500 * time.Millisecond)

	// Step 4: Try to confirm again (should fail)
	reqBody2 := fmt.Sprintf(`{"userId": %d, "code": "%s"}`, userID, confirmationCode)
	req2 := events.APIGatewayV2HTTPRequest{
		Body: reqBody2,
	}

	resp2, err := confirmHandler.Handle(ctx, req2)
	require.NoError(t, err)
	assert.Equal(t, 409, resp2.StatusCode)

	var errorResp models.ErrorResponse
	err = json.Unmarshal([]byte(resp2.Body), &errorResp)
	require.NoError(t, err)
	assert.Equal(t, "user_already_confirmed", errorResp.Code)
	assert.Equal(t, "User is already confirmed", errorResp.Message)
}
