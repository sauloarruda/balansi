package testhelpers

import (
	"context"
	"testing"

	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/stretchr/testify/require"
	"github.com/testcontainers/testcontainers-go"
	"github.com/testcontainers/testcontainers-go/modules/postgres"
	"github.com/testcontainers/testcontainers-go/wait"
)

// SetupTestDB creates a test PostgreSQL database using testcontainers
// Returns the connection pool and a cleanup function.
func SetupTestDB(t *testing.T) (*pgxpool.Pool, func()) {
	ctx := context.Background()

	postgresContainer, err := postgres.Run(ctx,
		"postgres:15-alpine",
		postgres.WithDatabase("testdb"),
		postgres.WithUsername("testuser"),
		postgres.WithPassword("testpass"),
		testcontainers.WithWaitStrategy(
			wait.ForLog("database system is ready to accept connections").
				WithOccurrence(2).
				WithStartupTimeout(30*time.Second)),
	)
	require.NoError(t, err)

	connStr, err := postgresContainer.ConnectionString(ctx, "sslmode=disable")
	require.NoError(t, err)

	pool, err := pgxpool.New(ctx, connStr)
	require.NoError(t, err)

	cleanup := func() {
		pool.Close()
		if err := postgresContainer.Terminate(ctx); err != nil {
			t.Logf("Failed to terminate postgres container: %v", err)
		}
	}

	return pool, cleanup
}

// CreateUsersTable creates the users table in the test database.
func CreateUsersTable(t *testing.T, pool *pgxpool.Pool) {
	ctx := context.Background()
	_, err := pool.Exec(ctx, `
		CREATE TABLE IF NOT EXISTS users (
			id SERIAL PRIMARY KEY,
			name VARCHAR(255) NOT NULL,
			email VARCHAR(255) NOT NULL UNIQUE,
			temporary_password TEXT,
			cognito_id VARCHAR(255),
			status VARCHAR(50) NOT NULL DEFAULT 'pending_confirmation',
			created_at TIMESTAMP NOT NULL DEFAULT NOW(),
			updated_at TIMESTAMP NOT NULL DEFAULT NOW()
		)
	`)
	require.NoError(t, err)
}

// CleanupUsersTable truncates the users table.
func CleanupUsersTable(t *testing.T, pool *pgxpool.Pool) {
	ctx := context.Background()
	_, err := pool.Exec(ctx, "TRUNCATE TABLE users RESTART IDENTITY CASCADE")
	require.NoError(t, err)
}

// SetupTestDBWithoutT creates a test PostgreSQL database without requiring *testing.T
// This is useful for TestMain where we don't have a valid *testing.T
func SetupTestDBWithoutT() (*pgxpool.Pool, func(), error) {
	ctx := context.Background()

	postgresContainer, err := postgres.Run(ctx,
		"postgres:15-alpine",
		postgres.WithDatabase("testdb"),
		postgres.WithUsername("testuser"),
		postgres.WithPassword("testpass"),
		testcontainers.WithWaitStrategy(
			wait.ForLog("database system is ready to accept connections").
				WithOccurrence(2).
				WithStartupTimeout(30*time.Second)),
	)
	if err != nil {
		return nil, nil, err
	}

	connStr, err := postgresContainer.ConnectionString(ctx, "sslmode=disable")
	if err != nil {
		postgresContainer.Terminate(ctx)
		return nil, nil, err
	}

	pool, err := pgxpool.New(ctx, connStr)
	if err != nil {
		postgresContainer.Terminate(ctx)
		return nil, nil, err
	}

	cleanup := func() {
		pool.Close()
		postgresContainer.Terminate(ctx)
	}

	return pool, cleanup, nil
}

// CreateUsersTableWithoutT creates the users table without requiring *testing.T
func CreateUsersTableWithoutT(pool *pgxpool.Pool) error {
	ctx := context.Background()
	_, err := pool.Exec(ctx, `
		CREATE TABLE IF NOT EXISTS users (
			id SERIAL PRIMARY KEY,
			name VARCHAR(255) NOT NULL,
			email VARCHAR(255) NOT NULL UNIQUE,
			temporary_password TEXT,
			cognito_id VARCHAR(255),
			status VARCHAR(50) NOT NULL DEFAULT 'pending_confirmation',
			created_at TIMESTAMP NOT NULL DEFAULT NOW(),
			updated_at TIMESTAMP NOT NULL DEFAULT NOW()
		)
	`)
	return err
}
