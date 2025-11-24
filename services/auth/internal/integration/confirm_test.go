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
	"services/auth/internal/models"
	"services/auth/internal/repositories"
	"services/auth/internal/services"
	"services/auth/internal/testhelpers"

	"github.com/aws/aws-lambda-go/events"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// tryConfirmationCodes attempts to find a working confirmation code by trying common codes
// Returns the first code that works, or empty string if none work
func tryConfirmationCodes(t *testing.T, handler *handlers.ConfirmHandler, ctx context.Context, userID int64, email string) string {
	// Common test codes used by cognito-local or test environments
	// cognito-local uses "123123" as the default confirmation code
	testCodes := []string{"123123", "123456", "000000", "111111", "1234567", "1234"}

	for _, code := range testCodes {
		reqBody := fmt.Sprintf(`{"userId": %d, "code": "%s"}`, userID, code)
		req := events.APIGatewayV2HTTPRequest{Body: reqBody}

		resp, err := handler.Handle(ctx, req)
		if err != nil {
			continue
		}

		if resp.StatusCode == 200 {
			return code
		}

		// If it's not an invalid code error, something else is wrong
		var errorResp models.ErrorResponse
		if json.Unmarshal([]byte(resp.Body), &errorResp) == nil {
			if errorResp.Code != "invalid_code" && errorResp.Code != "expired_code" {
				// Unexpected error, fail immediately
				t.Fatalf("Unexpected error when trying code %s: %s", code, resp.Body)
			}
		}
	}

	return ""
}

func TestConfirm_Integration_Success(t *testing.T) {
	if testing.Short() {
		t.Skip("Skipping integration test in short mode")
	}

	// Setup test database
	pool, cleanup := testhelpers.SetupTestDB(t)
	defer cleanup()

	testhelpers.CreateUsersTable(t, pool)

	// Setup Cognito client (using cognito-local if available)
	cfg := localTestConfig()

	cognitoClient, err := cognito.NewClient(cfg)
	if err != nil {
		t.Skipf("Skipping integration test - Cognito client setup failed: %v", err)
	}

	// Initialize dependencies
	userRepo := repositories.NewUserRepository(pool)
	signupService := services.NewSignupService(userRepo, cognitoClient, cfg.EncryptionSecret)
	confirmHandler := handlers.NewConfirmHandlerWithInterface(signupService)

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

	var tokenResp models.TokenResponse
	err = json.Unmarshal([]byte(resp.Body), &tokenResp)
	require.NoError(t, err)

	// Verify tokens are present
	assert.NotEmpty(t, tokenResp.AccessToken, "Access token should be present")
	assert.NotEmpty(t, tokenResp.IDToken, "ID token should be present")
	assert.NotEmpty(t, tokenResp.RefreshToken, "Refresh token should be present")
	// ExpiresIn might be 0 in cognito-local, so we just verify it's not negative
	assert.GreaterOrEqual(t, tokenResp.ExpiresIn, int32(0), "ExpiresIn should be >= 0")
	assert.Equal(t, "Bearer", tokenResp.TokenType, "Token type should be Bearer")

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

	// Setup test database
	pool, cleanup := testhelpers.SetupTestDB(t)
	defer cleanup()

	testhelpers.CreateUsersTable(t, pool)

	// Setup Cognito client
	cfg := localTestConfig()

	cognitoClient, err := cognito.NewClient(cfg)
	if err != nil {
		t.Skipf("Skipping integration test - Cognito client setup failed: %v", err)
	}

	userRepo := repositories.NewUserRepository(pool)
	signupService := services.NewSignupService(userRepo, cognitoClient, cfg.EncryptionSecret)
	confirmHandler := handlers.NewConfirmHandlerWithInterface(signupService)

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

	// Setup test database
	pool, cleanup := testhelpers.SetupTestDB(t)
	defer cleanup()

	testhelpers.CreateUsersTable(t, pool)

	// Setup Cognito client
	cfg := localTestConfig()

	cognitoClient, err := cognito.NewClient(cfg)
	if err != nil {
		t.Skipf("Skipping integration test - Cognito client setup failed: %v", err)
	}

	userRepo := repositories.NewUserRepository(pool)
	signupService := services.NewSignupService(userRepo, cognitoClient, cfg.EncryptionSecret)
	confirmHandler := handlers.NewConfirmHandlerWithInterface(signupService)

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

	// Setup test database
	pool, cleanup := testhelpers.SetupTestDB(t)
	defer cleanup()

	testhelpers.CreateUsersTable(t, pool)

	// Setup Cognito client
	cfg := localTestConfig()

	cognitoClient, err := cognito.NewClient(cfg)
	if err != nil {
		t.Skipf("Skipping integration test - Cognito client setup failed: %v", err)
	}

	userRepo := repositories.NewUserRepository(pool)
	signupService := services.NewSignupService(userRepo, cognitoClient, cfg.EncryptionSecret)
	confirmHandler := handlers.NewConfirmHandlerWithInterface(signupService)

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

func TestConfirm_Integration_EndToEnd(t *testing.T) {
	if testing.Short() {
		t.Skip("Skipping integration test in short mode")
	}

	// Setup test database
	pool, cleanup := testhelpers.SetupTestDB(t)
	defer cleanup()

	testhelpers.CreateUsersTable(t, pool)

	// Setup Cognito client
	cfg := localTestConfig()

	cognitoClient, err := cognito.NewClient(cfg)
	if err != nil {
		t.Skipf("Skipping integration test - Cognito client setup failed: %v", err)
	}

	userRepo := repositories.NewUserRepository(pool)
	signupService := services.NewSignupService(userRepo, cognitoClient, cfg.EncryptionSecret)
	confirmHandler := handlers.NewConfirmHandlerWithInterface(signupService)

	ctx := context.Background()
	name := "E2E Test User"
	email := fmt.Sprintf("e2e-%d@example.com", time.Now().UnixNano())

	// Step 1: Signup
	signupResult, err := signupService.Signup(ctx, name, email)
	if err != nil {
		if errors.Is(err, services.ErrSignupProviderUnavailable) {
			t.Skipf("Skipping integration test - signup provider not available: %v", err)
			return
		}
		require.NoError(t, err)
	}

	require.NotNil(t, signupResult)
	require.NotNil(t, signupResult.User)
	assert.Equal(t, models.SignupStatusPendingConfirmation, signupResult.Status)

	userID := signupResult.User.ID
	require.NotNil(t, signupResult.User.TemporaryPassword)

	// Verify password can be decrypted
	decryptedPassword, err := encryption.Decrypt(*signupResult.User.TemporaryPassword, cfg.EncryptionSecret)
	require.NoError(t, err)
	assert.NotEmpty(t, decryptedPassword)

	// Wait for Cognito to process
	time.Sleep(500 * time.Millisecond)

	// Step 2: Confirm with cognito-local's default code
	confirmationCode := "123123"
	reqBody := fmt.Sprintf(`{"userId": %d, "code": "%s"}`, userID, confirmationCode)
	req := events.APIGatewayV2HTTPRequest{
		Body: reqBody,
	}

	resp, err := confirmHandler.Handle(ctx, req)
	require.NoError(t, err)
	require.Equal(t, 200, resp.StatusCode, "Expected success: %s", resp.Body)

	// Verify tokens
	var tokenResp models.TokenResponse
	err = json.Unmarshal([]byte(resp.Body), &tokenResp)
	require.NoError(t, err)

	assert.NotEmpty(t, tokenResp.AccessToken)
	assert.NotEmpty(t, tokenResp.IDToken)
	assert.NotEmpty(t, tokenResp.RefreshToken)

	// Verify user is confirmed in database
	confirmedUser, err := userRepo.FindByID(ctx, userID)
	require.NoError(t, err)
	require.NotNil(t, confirmedUser)
	assert.Equal(t, models.UserStatusConfirmed, confirmedUser.Status)

	// Verify we can use the tokens to authenticate (optional - would require another endpoint)
	// For now, we just verify the tokens are valid format
	assert.Greater(t, len(tokenResp.AccessToken), 100, "Access token should be substantial length")
	assert.Greater(t, len(tokenResp.IDToken), 100, "ID token should be substantial length")
}
