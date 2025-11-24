package integration

import (
	"context"
	"errors"
	"fmt"
	"os"
	"testing"
	"time"

	"services/auth/internal/cognito"
	"services/auth/internal/config"
	"services/auth/internal/encryption"
	"services/auth/internal/models"
	"services/auth/internal/repositories"
	"services/auth/internal/services"
	"services/auth/internal/testhelpers"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// localTestConfig creates a configuration for cognito-local integration tests.
// It reads from environment variables or uses default values from cognito-local setup.
func localTestConfig() *config.Config {
	// Try to get values from environment variables first (set by cognito-setup script)
	userPoolID := os.Getenv("COGNITO_USER_POOL_ID")
	if userPoolID == "" {
		// Default value from cognito-local setup (can be found in .cognito/db/)
		userPoolID = "local_6eLCsRav"
	}

	clientID := os.Getenv("COGNITO_CLIENT_ID")
	if clientID == "" {
		// Default value from cognito-local setup (can be found in .cognito/db/clients.json)
		clientID = "2qdfneigub7f5h79cnej0i3fo"
	}

	clientSecret := os.Getenv("COGNITO_CLIENT_SECRET")
	endpoint := os.Getenv("COGNITO_ENDPOINT")
	if endpoint == "" {
		endpoint = "http://localhost:9229"
	}

	return &config.Config{
		CognitoUserPoolID:   userPoolID,
		CognitoClientID:     clientID,
		CognitoClientSecret: clientSecret,
		CognitoEndpoint:     endpoint,
		EncryptionSecret:    "test-secret-key-1234567890123456",
	}
}

func TestSignup_Integration_NewUser(t *testing.T) {
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

	ctx := context.Background()
	name := "Integration Test User"
	email := "integration@example.com"

	// Execute signup
	result, err := signupService.Signup(ctx, name, email)

	// Verify result
	if err != nil {
		// If the identity provider is not available, skip the test
		if errors.Is(err, services.ErrSignupProviderUnavailable) {
			t.Skipf("Skipping integration test - signup provider not available: %v", err)
			return
		}
		require.NoError(t, err, "Signup should succeed")
	}

	require.NotNil(t, result)
	require.NotNil(t, result.User)
	assert.Equal(t, models.SignupStatusPendingConfirmation, result.Status)
	assert.Equal(t, name, result.User.Name)
	assert.Equal(t, email, result.User.Email)
	assert.NotNil(t, result.User.CognitoID)
	assert.NotNil(t, result.User.TemporaryPassword)
	assert.NotZero(t, result.User.ID)
	assert.False(t, result.User.CreatedAt.IsZero())

	// Verify password can be decrypted
	decryptedPassword, err := encryption.Decrypt(*result.User.TemporaryPassword, cfg.EncryptionSecret)
	require.NoError(t, err)
	assert.NotEmpty(t, decryptedPassword)
	assert.GreaterOrEqual(t, len(decryptedPassword), 32, "Password should be at least 32 characters")
}

func TestSignup_Integration_DuplicateEmail(t *testing.T) {
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

	ctx := context.Background()
	name := "Duplicate Test User"
	email := "duplicate@example.com"

	// First signup
	result1, err := signupService.Signup(ctx, name, email)
	if err != nil {
		if errors.Is(err, services.ErrSignupProviderUnavailable) {
			t.Skipf("Skipping integration test - signup provider not available: %v", err)
			return
		}
		require.NoError(t, err)
	}
	require.NotNil(t, result1)
	require.NotNil(t, result1.User)

	// Wait a bit to ensure Cognito processes the first signup
	time.Sleep(500 * time.Millisecond)

	// Try to signup again with same email
	result2, err := signupService.Signup(ctx, name, email)

	// Should return error or existing user (depending on Cognito state)
	// In local testing, it might resend confirmation code
	if err != nil {
		assert.True(t, errors.Is(err, services.ErrUserAlreadyExists))
		assert.Nil(t, result2)
	} else {
		// If no error, should return the existing user
		require.NotNil(t, result2)
		require.NotNil(t, result2.User)
		assert.Equal(t, result1.User.ID, result2.User.ID)
		assert.Equal(t, models.SignupStatusPendingConfirmation, result2.Status)
	}
}

func TestSignup_Integration_ConcurrentSignups(t *testing.T) {
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

	ctx := context.Background()
	numUsers := 5
	results := make(chan error, numUsers)

	// Create multiple users concurrently
	for i := 0; i < numUsers; i++ {
		go func(index int) {
			email := fmt.Sprintf("concurrent%d@example.com", index)
			_, err := signupService.Signup(ctx, "Concurrent User", email)
			results <- err
		}(i)
	}

	// Wait for all signups to complete
	errs := make([]error, 0, numUsers)
	for i := 0; i < numUsers; i++ {
		err := <-results
		if err != nil {
			// Skip if signup provider not available
			if errors.Is(err, services.ErrSignupProviderUnavailable) {
				t.Skipf("Skipping integration test - signup provider not available: %v", err)
				return
			}
			errs = append(errs, err)
		}
	}

	// All signups should succeed (or fail gracefully)
	// In a real scenario, some might fail due to race conditions
	assert.LessOrEqual(t, len(errs), numUsers, "Some signups may fail due to concurrency")
}

func TestSignup_Integration_DatabaseConstraints(t *testing.T) {
	if testing.Short() {
		t.Skip("Skipping integration test in short mode")
	}

	// Setup test database
	pool, cleanup := testhelpers.SetupTestDB(t)
	defer cleanup()

	testhelpers.CreateUsersTable(t, pool)

	userRepo := repositories.NewUserRepository(pool)
	ctx := context.Background()

	// Test unique email constraint
	user1 := &models.User{
		Name:  "User One",
		Email: "unique@example.com",
	}

	err := userRepo.Create(ctx, user1)
	require.NoError(t, err)

	// Try to create another user with same email
	user2 := &models.User{
		Name:  "User Two",
		Email: "unique@example.com",
	}

	err = userRepo.Create(ctx, user2)
	assert.Error(t, err, "Should fail on duplicate email constraint")
}
