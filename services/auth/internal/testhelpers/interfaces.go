package testhelpers

import (
	"context"
	"services/auth/internal/models"
)

// UserRepositoryInterface defines the interface for user repository operations.
type UserRepositoryInterface interface {
	FindByEmail(ctx context.Context, email string) (*models.User, error)
	Create(ctx context.Context, user *models.User) error
	Update(ctx context.Context, user *models.User) error
}

// CognitoClientInterface defines the interface for Cognito client operations.
type CognitoClientInterface interface {
	SignUp(ctx context.Context, email, password, name string) (string, error)
	IsUserConfirmed(ctx context.Context, email string) (bool, string, string, error)
	ResendConfirmationCode(ctx context.Context, username string) error
	ConfirmSignUp(ctx context.Context, cognitoID string, confirmationCode string) error
}
