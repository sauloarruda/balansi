package testhelpers

import (
	"context"
	"services/auth/internal/models"

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

func (m *MockCognitoClient) ConfirmSignUp(ctx context.Context, cognitoID string, confirmationCode string) error {
	args := m.Called(ctx, cognitoID, confirmationCode)
	return args.Error(0)
}
