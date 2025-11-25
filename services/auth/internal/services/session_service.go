package services

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"services/auth/internal/cognito"
	"services/auth/internal/encryption"
	"services/auth/internal/models"
	"services/auth/internal/repositories"
	"services/auth/internal/testhelpers"

	"github.com/aws/aws-sdk-go-v2/aws"
)

var (
	ErrInvalidSession     = errors.New("invalid session")
	ErrSessionExpired     = errors.New("session expired")
	ErrUserNotConfirmed   = errors.New("user not confirmed")
	ErrRefreshTokenFailed = errors.New("failed to refresh token")
)

type SessionService struct {
	userRepo         testhelpers.UserRepositoryInterface
	cognitoClient    testhelpers.CognitoClientInterface
	encryptFunc      func(string, string) (string, error)
	decryptFunc      func(string, string) (string, error)
	encryptionSecret string
}

func NewSessionService(
	userRepo *repositories.UserRepository,
	cognitoClient *cognito.Client,
	encryptionSecret string,
) *SessionService {
	return NewSessionServiceWithInterfaces(userRepo, cognitoClient, encryptionSecret)
}

func NewSessionServiceWithInterfaces(
	userRepo testhelpers.UserRepositoryInterface,
	cognitoClient testhelpers.CognitoClientInterface,
	encryptionSecret string,
) *SessionService {
	return &SessionService{
		userRepo:         userRepo,
		cognitoClient:    cognitoClient,
		encryptFunc:      encryption.Encrypt,
		decryptFunc:      encryption.Decrypt,
		encryptionSecret: encryptionSecret,
	}
}

// EncryptSessionData encrypts session data (refresh token, userID, username) for storage in cookie
func (s *SessionService) EncryptSessionData(sessionData *models.SessionCookieData) (string, error) {
	// Serialize to JSON
	jsonData, err := json.Marshal(sessionData)
	if err != nil {
		return "", fmt.Errorf("failed to marshal session data: %w", err)
	}

	// Encrypt the JSON string
	return s.encryptFunc(string(jsonData), s.encryptionSecret)
}

// DecryptSessionData decrypts session data from cookie
func (s *SessionService) DecryptSessionData(encryptedData string) (*models.SessionCookieData, error) {
	// Decrypt
	decrypted, err := s.decryptFunc(encryptedData, s.encryptionSecret)
	if err != nil {
		return nil, fmt.Errorf("%w: %v", ErrInvalidSession, err)
	}

	// Deserialize from JSON
	var sessionData models.SessionCookieData
	if err := json.Unmarshal([]byte(decrypted), &sessionData); err != nil {
		return nil, fmt.Errorf("%w: failed to unmarshal session data: %v", ErrInvalidSession, err)
	}

	return &sessionData, nil
}

// RefreshAccessToken uses the session data from cookie to get a new access token
// Validates that the user is confirmed before returning tokens
func (s *SessionService) RefreshAccessToken(ctx context.Context, encryptedSessionData string) (*models.AccessTokenResponse, error) {
	// Decrypt session data
	sessionData, err := s.DecryptSessionData(encryptedSessionData)
	if err != nil {
		return nil, err
	}

	// Verify user is confirmed
	user, err := s.userRepo.FindByID(ctx, sessionData.UserID)
	if err != nil {
		return nil, fmt.Errorf("failed to find user: %w", err)
	}
	if user == nil {
		return nil, ErrInvalidSession
	}

	if user.Status != models.UserStatusConfirmed {
		return nil, ErrUserNotConfirmed
	}

	// Refresh token using Cognito
	authResult, err := s.cognitoClient.RefreshTokenWithUsername(ctx, sessionData.RefreshToken, sessionData.Username)
	if err != nil {
		return nil, fmt.Errorf("%w: %v", ErrRefreshTokenFailed, err)
	}

	return &models.AccessTokenResponse{
		AccessToken: aws.ToString(authResult.AccessToken),
		ExpiresIn:   authResult.ExpiresIn,
	}, nil
}
