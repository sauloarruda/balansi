package repositories

import (
	"context"
	"os"
	"testing"
	"time"

	"services/auth/internal/models"
	"services/auth/internal/testhelpers"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

var sharedDBPool *pgxpool.Pool
var sharedCleanup func()

func TestMain(m *testing.M) {
	// Setup shared database for all tests
	pool, cleanup, err := testhelpers.SetupTestDBWithoutT()
	if err != nil {
		os.Exit(1)
	}
	sharedDBPool = pool
	sharedCleanup = cleanup

	// Create users table once
	if err := testhelpers.CreateUsersTableWithoutT(pool); err != nil {
		cleanup()
		os.Exit(1)
	}

	// Run tests
	code := m.Run()

	// Cleanup
	if sharedCleanup != nil {
		sharedCleanup()
	}
	os.Exit(code)
}

func TestUserRepository_FindByEmail(t *testing.T) {
	// Clean table before each test
	testhelpers.CleanupUsersTable(t, sharedDBPool)

	repo := NewUserRepository(sharedDBPool)
	ctx := context.Background()

	t.Run("user not found", func(t *testing.T) {
		user, err := repo.FindByEmail(ctx, "nonexistent@example.com")
		assert.NoError(t, err)
		assert.Nil(t, user)
	})

	t.Run("user found", func(t *testing.T) {
		// Create a user first
		user := &models.User{
			Name:      "John Doe",
			Email:     "john@example.com",
			CognitoID: stringPtr("cognito-123"),
		}
		err := repo.Create(ctx, user)
		require.NoError(t, err)

		// Find the user
		found, err := repo.FindByEmail(ctx, "john@example.com")
		require.NoError(t, err)
		require.NotNil(t, found)

		assert.Equal(t, user.ID, found.ID)
		assert.Equal(t, user.Name, found.Name)
		assert.Equal(t, user.Email, found.Email)
		assert.Equal(t, user.CognitoID, found.CognitoID)
		assert.False(t, found.CreatedAt.IsZero())
		assert.False(t, found.UpdatedAt.IsZero())
	})
}

func TestUserRepository_Create(t *testing.T) {
	// Clean table before each test
	testhelpers.CleanupUsersTable(t, sharedDBPool)

	repo := NewUserRepository(sharedDBPool)
	ctx := context.Background()

	t.Run("create new user", func(t *testing.T) {
		user := &models.User{
			Name:              "Jane Doe",
			Email:             "jane@example.com",
			TemporaryPassword: stringPtr("encrypted-password"),
			CognitoID:         stringPtr("cognito-456"),
		}

		err := repo.Create(ctx, user)
		require.NoError(t, err)
		assert.NotZero(t, user.ID)
		assert.False(t, user.CreatedAt.IsZero())
		assert.False(t, user.UpdatedAt.IsZero())

		// Verify user was created
		found, err := repo.FindByEmail(ctx, "jane@example.com")
		require.NoError(t, err)
		require.NotNil(t, found)
		assert.Equal(t, user.Name, found.Name)
		assert.Equal(t, user.Email, found.Email)
	})

	t.Run("create user with nil fields", func(t *testing.T) {
		user := &models.User{
			Name:  "Bob Smith",
			Email: "bob@example.com",
			// TemporaryPassword and CognitoID are nil
		}

		err := repo.Create(ctx, user)
		require.NoError(t, err)
		assert.NotZero(t, user.ID)
	})

	t.Run("duplicate email", func(t *testing.T) {
		user1 := &models.User{
			Name:  "User One",
			Email: "duplicate@example.com",
		}
		err := repo.Create(ctx, user1)
		require.NoError(t, err)

		user2 := &models.User{
			Name:  "User Two",
			Email: "duplicate@example.com",
		}
		err = repo.Create(ctx, user2)
		assert.Error(t, err, "Should fail on duplicate email")
	})
}

func TestUserRepository_Update(t *testing.T) {
	// Clean table before each test
	testhelpers.CleanupUsersTable(t, sharedDBPool)

	repo := NewUserRepository(sharedDBPool)
	ctx := context.Background()

	t.Run("update existing user", func(t *testing.T) {
		// Create a user
		user := &models.User{
			Name:      "Original Name",
			Email:     "update@example.com",
			CognitoID: stringPtr("cognito-original"),
		}
		err := repo.Create(ctx, user)
		require.NoError(t, err)

		originalUpdatedAt := user.UpdatedAt

		// Wait a bit to ensure updated_at changes
		time.Sleep(10 * time.Millisecond)

		// Update the user
		user.Name = "Updated Name"
		user.TemporaryPassword = stringPtr("new-encrypted-password")
		user.CognitoID = stringPtr("cognito-updated")

		err = repo.Update(ctx, user)
		require.NoError(t, err)
		assert.True(t, user.UpdatedAt.After(originalUpdatedAt), "UpdatedAt should be updated")

		// Verify changes
		found, err := repo.FindByEmail(ctx, "update@example.com")
		require.NoError(t, err)
		require.NotNil(t, found)
		assert.Equal(t, "Updated Name", found.Name)
		assert.Equal(t, "new-encrypted-password", *found.TemporaryPassword)
		assert.Equal(t, "cognito-updated", *found.CognitoID)
	})

	t.Run("update non-existent user", func(t *testing.T) {
		user := &models.User{
			ID:    99999,
			Name:  "Non-existent",
			Email: "nonexistent@example.com",
		}
		err := repo.Update(ctx, user)
		assert.Error(t, err, "Should fail when updating non-existent user")
	})
}

func stringPtr(s string) *string {
	return &s
}
