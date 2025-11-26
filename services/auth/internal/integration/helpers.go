package integration

import (
	"os"
	"strings"
	"testing"

	"services/auth/internal/config"
	"services/auth/internal/testhelpers"

	"github.com/jackc/pgx/v5/pgxpool"
)

// IntegrationTestSetup holds the common setup components for integration tests
type IntegrationTestSetup struct {
	Cfg            *config.Config
	Cleanup        func()
	Pool           *pgxpool.Pool
}

// setupIntegrationTest creates a common setup for integration tests
// Returns the config and cleanup function
func setupIntegrationTest(t *testing.T) *IntegrationTestSetup {
	t.Helper()

	// Setup test database
	pool, cleanup := testhelpers.SetupTestDB(t)

	// Create users table
	testhelpers.CreateUsersTable(t, pool)

	return &IntegrationTestSetup{
		Cfg:     localTestConfig(),
		Cleanup: cleanup,
		Pool:    pool,
	}
}

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

// extractSessionID extracts the session_id value from Set-Cookie header
func extractSessionID(cookieHeader string) string {
	// Format: "session_id=value; Path=/; HttpOnly; ..."
	parts := strings.Split(cookieHeader, ";")
	if len(parts) == 0 {
		return ""
	}
	sessionPart := strings.TrimSpace(parts[0])
	if strings.HasPrefix(sessionPart, "session_id=") {
		return strings.TrimPrefix(sessionPart, "session_id=")
	}
	return ""
}
