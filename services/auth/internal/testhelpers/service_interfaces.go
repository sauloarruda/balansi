package testhelpers

import (
	"context"
	"services/auth/internal/models"
)

// SignupServiceInterface defines the interface for signup service operations.
type SignupServiceInterface interface {
	Signup(ctx context.Context, name, email string) (*models.SignupOutcome, error)
	Confirm(ctx context.Context, userID int64, code string) (*models.AuthenticationTokenResult, error)
}

// PasswordRecoveryServiceInterface defines the interface for password recovery service operations.
type PasswordRecoveryServiceInterface interface {
	ForgotPassword(ctx context.Context, email string) (*models.ForgotPasswordResult, error)
	ResetPassword(ctx context.Context, email, code, newPassword string) error
}
