package testhelpers

import (
	"context"
	"services/auth/internal/models"

	"github.com/aws/aws-sdk-go-v2/service/cognitoidentityprovider/types"
	"github.com/stretchr/testify/mock"
)

// MockUserRepository is a mock implementation of UserRepositoryInterface.
type MockUserRepository struct {
	mock.Mock
}

func (m *MockUserRepository) FindByEmail(ctx context.Context, email string) (*models.User, error) {
	args := m.Called(ctx, email)
	if args.Get(0) == nil {
		return nil, args.Error(1)
	}
	return args.Get(0).(*models.User), args.Error(1)
}

func (m *MockUserRepository) FindByID(ctx context.Context, id int64) (*models.User, error) {
	args := m.Called(ctx, id)
	if args.Get(0) == nil {
		return nil, args.Error(1)
	}
	return args.Get(0).(*models.User), args.Error(1)
}

func (m *MockUserRepository) FindByCognitoID(ctx context.Context, cognitoID string) (*models.User, error) {
	args := m.Called(ctx, cognitoID)
	if args.Get(0) == nil {
		return nil, args.Error(1)
	}
	return args.Get(0).(*models.User), args.Error(1)
}

func (m *MockUserRepository) Create(ctx context.Context, user *models.User) error {
	args := m.Called(ctx, user)
	return args.Error(0)
}

func (m *MockUserRepository) Update(ctx context.Context, user *models.User) error {
	args := m.Called(ctx, user)
	return args.Error(0)
}

// MockCognitoClient is a mock implementation of CognitoClientInterface.
type MockCognitoClient struct {
	mock.Mock
}

func (m *MockCognitoClient) SignUp(ctx context.Context, email, password, name string) (string, error) {
	args := m.Called(ctx, email, password, name)
	return args.String(0), args.Error(1)
}

func (m *MockCognitoClient) IsUserConfirmed(ctx context.Context, email string) (bool, string, string, error) {
	args := m.Called(ctx, email)
	return args.Bool(0), args.String(1), args.String(2), args.Error(3)
}

func (m *MockCognitoClient) ResendConfirmationCode(ctx context.Context, username string) error {
	args := m.Called(ctx, username)
	return args.Error(0)
}

func (m *MockCognitoClient) ConfirmSignUp(ctx context.Context, cognitoID string, confirmationCode string, usernameOrEmail ...string) error {
	args := m.Called(ctx, cognitoID, confirmationCode, usernameOrEmail)
	return args.Error(0)
}

func (m *MockCognitoClient) GetUsernameByUserSub(ctx context.Context, userSub string, email ...string) (string, error) {
	args := m.Called(ctx, userSub, email)
	return args.String(0), args.Error(1)
}

func (m *MockCognitoClient) InitiateAuth(ctx context.Context, cognitoID, password string) (*types.AuthenticationResultType, error) {
	args := m.Called(ctx, cognitoID, password)
	if args.Get(0) == nil {
		return nil, args.Error(1)
	}
	return args.Get(0).(*types.AuthenticationResultType), args.Error(1)
}

func (m *MockCognitoClient) RefreshTokenWithUsername(ctx context.Context, refreshToken, username string) (*types.AuthenticationResultType, error) {
	args := m.Called(ctx, refreshToken, username)
	if args.Get(0) == nil {
		return nil, args.Error(1)
	}
	return args.Get(0).(*types.AuthenticationResultType), args.Error(1)
}

func (m *MockCognitoClient) ForgotPassword(ctx context.Context, email string) (*types.CodeDeliveryDetailsType, error) {
	args := m.Called(ctx, email)
	if args.Get(0) == nil {
		return nil, args.Error(1)
	}
	return args.Get(0).(*types.CodeDeliveryDetailsType), args.Error(1)
}

func (m *MockCognitoClient) ResetPassword(ctx context.Context, email, code, newPassword string) error {
	args := m.Called(ctx, email, code, newPassword)
	return args.Error(0)
}

// MockSignupService is a mock implementation of SignupServiceInterface.
type MockSignupService struct {
	mock.Mock
}

func (m *MockSignupService) Signup(ctx context.Context, name, email string) (*models.SignupOutcome, error) {
	args := m.Called(ctx, name, email)
	if args.Get(0) == nil {
		return nil, args.Error(1)
	}
	return args.Get(0).(*models.SignupOutcome), args.Error(1)
}

func (m *MockSignupService) Confirm(ctx context.Context, userID int64, code string) (*models.AuthenticationTokenResult, error) {
	args := m.Called(ctx, userID, code)
	if args.Get(0) == nil {
		return nil, args.Error(1)
	}
	return args.Get(0).(*models.AuthenticationTokenResult), args.Error(1)
}
