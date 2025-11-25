package testhelpers

import (
	"context"
	"services/auth/internal/models"

	"github.com/stretchr/testify/mock"
)

// SessionServiceInterface defines the interface for session service operations
type SessionServiceInterface interface {
	EncryptSessionData(sessionData *models.SessionCookieData) (string, error)
	DecryptSessionData(encryptedData string) (*models.SessionCookieData, error)
	RefreshAccessToken(ctx context.Context, encryptedSessionData string) (*models.AccessTokenResponse, error)
}

// MockSessionService is a mock implementation of SessionServiceInterface
type MockSessionService struct {
	mock.Mock
}

func (m *MockSessionService) EncryptSessionData(sessionData *models.SessionCookieData) (string, error) {
	args := m.Called(sessionData)
	return args.String(0), args.Error(1)
}

func (m *MockSessionService) DecryptSessionData(encryptedData string) (*models.SessionCookieData, error) {
	args := m.Called(encryptedData)
	if args.Get(0) == nil {
		return nil, args.Error(1)
	}
	return args.Get(0).(*models.SessionCookieData), args.Error(1)
}

func (m *MockSessionService) RefreshAccessToken(ctx context.Context, encryptedSessionData string) (*models.AccessTokenResponse, error) {
	args := m.Called(ctx, encryptedSessionData)
	if args.Get(0) == nil {
		return nil, args.Error(1)
	}
	return args.Get(0).(*models.AccessTokenResponse), args.Error(1)
}
