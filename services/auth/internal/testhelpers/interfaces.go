package testhelpers

import (
	"context"
	"services/auth/internal/models"

	"github.com/aws/aws-sdk-go-v2/service/cognitoidentityprovider/types"
)

// UserRepositoryInterface defines the interface for user repository operations.
type UserRepositoryInterface interface {
	FindByEmail(ctx context.Context, email string) (*models.User, error)
	FindByID(ctx context.Context, id int64) (*models.User, error)
	Create(ctx context.Context, user *models.User) error
	Update(ctx context.Context, user *models.User) error
}

// CognitoClientInterface defines the interface for Cognito client operations.
type CognitoClientInterface interface {
	SignUp(ctx context.Context, email, password, name string) (string, error)        // Returns UserSub
	IsUserConfirmed(ctx context.Context, email string) (bool, string, string, error) // Returns isConfirmed, username, userSub
	GetUsernameByUserSub(ctx context.Context, userSub string, email ...string) (string, error)
	ResendConfirmationCode(ctx context.Context, username string) error
	ConfirmSignUp(ctx context.Context, cognitoID string, confirmationCode string, usernameOrEmail ...string) error // cognitoID is UserSub
	InitiateAuth(ctx context.Context, cognitoID, password string) (*types.AuthenticationResultType, error)         // cognitoID is UserSub
}
