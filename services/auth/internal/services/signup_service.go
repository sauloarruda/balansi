package services

import (
	"context"
	"crypto/rand"
	"errors"
	"fmt"
	"services/auth/internal/cognito"
	"services/auth/internal/encryption"
	"services/auth/internal/models"
	"services/auth/internal/repositories"
	"services/auth/internal/testhelpers"

	"github.com/aws/aws-sdk-go-v2/service/cognitoidentityprovider/types"
)

// UserRepositoryInterface defines repository operations (aliased for convenience).
type UserRepositoryInterface = testhelpers.UserRepositoryInterface

// CognitoClientInterface defines Cognito client operations (aliased for convenience).
type CognitoClientInterface = testhelpers.CognitoClientInterface

type SignupService struct {
	userRepo         UserRepositoryInterface
	cognitoClient    CognitoClientInterface
	encryptFunc      func(string, string) (string, error)
	decryptFunc      func(string, string) (string, error)
	encryptionSecret string
}

// NewSignupService creates a new SignupService with concrete implementations.
func NewSignupService(
	userRepo *repositories.UserRepository,
	cognitoClient *cognito.Client,
	encryptionSecret string,
) *SignupService {
	return NewSignupServiceWithInterfaces(userRepo, cognitoClient, encryptionSecret)
}

// NewSignupServiceWithInterfaces creates a new SignupService with interface-based dependencies
// This allows for easier testing with mocks.
func NewSignupServiceWithInterfaces(
	userRepo UserRepositoryInterface,
	cognitoClient CognitoClientInterface,
	encryptionSecret string,
) *SignupService {
	return &SignupService{
		userRepo:         userRepo,
		cognitoClient:    cognitoClient,
		encryptFunc:      encryption.Encrypt,
		decryptFunc:      encryption.Decrypt,
		encryptionSecret: encryptionSecret,
	}
}

func generateTemporaryPassword(length int) (string, error) {
	const (
		lowercase = "abcdefghijklmnopqrstuvwxyz"
		uppercase = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
		numbers   = "0123456789"
		special   = "!@#$%^&*()-_+=<>?"
		allChars  = lowercase + uppercase + numbers + special
	)

	if length < 4 {
		length = 4 // Minimum length to satisfy all requirements
	}

	password := make([]byte, length)

	// Ensure at least one character from each required category
	// Select random character from each category
	categories := []string{
		lowercase,
		uppercase,
		numbers,
		special,
	}

	for _, category := range categories {
		randomByte := make([]byte, 1)
		if _, err := rand.Read(randomByte); err != nil {
			return "", fmt.Errorf("failed to generate random byte: %w", err)
		}
		char := category[int(randomByte[0])%len(category)]

		// Place at random position
		randomByte = make([]byte, 1)
		if _, err := rand.Read(randomByte); err != nil {
			return "", fmt.Errorf("failed to generate random byte: %w", err)
		}
		pos := int(randomByte[0]) % length
		// Make sure we don't overwrite a previously placed required char
		for password[pos] != 0 {
			pos = (pos + 1) % length
		}
		password[pos] = char
	}

	// Fill remaining positions with random characters from allChars
	for i := range password {
		if password[i] == 0 {
			randomByte := make([]byte, 1)
			if _, err := rand.Read(randomByte); err != nil {
				return "", fmt.Errorf("failed to generate random byte: %w", err)
			}
			password[i] = allChars[int(randomByte[0])%len(allChars)]
		}
	}

	// Shuffle the password to randomize positions
	// This ensures required chars aren't always at the beginning
	for i := len(password) - 1; i > 0; i-- {
		randomByte := make([]byte, 1)
		if _, err := rand.Read(randomByte); err != nil {
			return "", fmt.Errorf("failed to generate random byte: %w", err)
		}
		j := int(randomByte[0]) % (i + 1)
		password[i], password[j] = password[j], password[i]
	}

	return string(password), nil
}

func (s *SignupService) Signup(ctx context.Context, name, email string) (*SignupResult, error) {
	// Check if user already exists
	existingUser, err := s.userRepo.FindByEmail(ctx, email)
	if err != nil {
		return nil, fmt.Errorf("failed to check existing user: %w", err)
	}

	if existingUser != nil && existingUser.CognitoID != nil {
		result, existingErr := s.handleExistingConfirmedUser(ctx, existingUser, email)
		if result != nil || existingErr != nil {
			if existingErr != nil {
				return nil, existingErr
			}
			return result, nil
		}
	}

	temporaryPassword, encryptedPassword, err := s.generateProtectedPassword()
	if err != nil {
		return nil, err
	}

	cognitoID, err := s.cognitoClient.SignUp(ctx, email, temporaryPassword, name)
	if err != nil {
		result, handledErr := s.handleCognitoSignUpError(ctx, err, existingUser, name, email, encryptedPassword)
		if handledErr != nil {
			return nil, handledErr
		}
		if result != nil {
			return result, nil
		}
		return nil, ErrSignupProviderUnavailable
	}

	user := s.buildUser(existingUser, name, email, &cognitoID, &encryptedPassword)
	if err := s.saveUser(ctx, user, existingUser != nil); err != nil {
		return nil, err
	}

	// New users in Cognito always start as UNCONFIRMED and need email confirmation
	return &SignupResult{
		User:   user,
		Status: models.SignupStatusPendingConfirmation,
	}, nil
}

func (s *SignupService) handleExistingConfirmedUser(ctx context.Context, existingUser *models.User, email string) (*SignupResult, error) {
	isConfirmed, username, cognitoID, checkErr := s.cognitoClient.IsUserConfirmed(ctx, email)
	if checkErr != nil {
		return nil, ErrUserAlreadyExists
	}

	if !isConfirmed {
		if resendErr := s.cognitoClient.ResendConfirmationCode(ctx, username); resendErr != nil {
			return nil, fmt.Errorf("failed to resend confirmation code: %w", resendErr)
		}

		if cognitoID != "" && existingUser.CognitoID == nil {
			existingUser.CognitoID = &cognitoID
			if err := s.userRepo.Update(ctx, existingUser); err != nil {
				return nil, fmt.Errorf("failed to update user: %w", err)
			}
		}

		return &SignupResult{
			User:   existingUser,
			Status: models.SignupStatusPendingConfirmation,
		}, nil
	}

	return nil, ErrUserAlreadyExists
}

func (s *SignupService) generateProtectedPassword() (string, string, error) {
	temporaryPassword, err := generateTemporaryPassword(32)
	if err != nil {
		return "", "", fmt.Errorf("failed to generate temporary password: %w", err)
	}

	encryptedPassword, err := s.encryptFunc(temporaryPassword, s.encryptionSecret)
	if err != nil {
		return "", "", fmt.Errorf("failed to encrypt password: %w", err)
	}

	return temporaryPassword, encryptedPassword, nil
}

func (s *SignupService) handleCognitoSignUpError(
	ctx context.Context,
	signupErr error,
	existingUser *models.User,
	name,
	email,
	encryptedPassword string,
) (*SignupResult, error) {
	var usernameExistsErr *types.UsernameExistsException
	if !errors.As(signupErr, &usernameExistsErr) {
		return nil, ErrSignupProviderUnavailable
	}

	isConfirmed, username, cognitoID, checkErr := s.cognitoClient.IsUserConfirmed(ctx, email)
	if checkErr != nil {
		return nil, ErrUserAlreadyExists
	}

	if isConfirmed {
		return nil, ErrUserAlreadyExists
	}

	if resendErr := s.cognitoClient.ResendConfirmationCode(ctx, username); resendErr != nil {
		return nil, fmt.Errorf("failed to resend confirmation code: %w", resendErr)
	}

	user := existingUser
	if user == nil {
		user = &models.User{}
	}

	user.Name = name
	user.Email = email
	user.CognitoID = &cognitoID
	if encryptedPassword != "" {
		user.TemporaryPassword = &encryptedPassword
	}

	if err := s.saveUser(ctx, user, existingUser != nil); err != nil {
		return nil, err
	}

	return &SignupResult{
		User:   user,
		Status: models.SignupStatusPendingConfirmation,
	}, nil
}

func (s *SignupService) buildUser(existingUser *models.User, name, email string, cognitoID, encryptedPassword *string) *models.User {
	user := &models.User{
		Name:              name,
		Email:             email,
		TemporaryPassword: encryptedPassword,
		CognitoID:         cognitoID,
	}

	if existingUser != nil {
		user.ID = existingUser.ID
	}

	return user
}

func (s *SignupService) saveUser(ctx context.Context, user *models.User, update bool) error {
	if update {
		if err := s.userRepo.Update(ctx, user); err != nil {
			return fmt.Errorf("failed to update user: %w", err)
		}
		return nil
	}

	if err := s.userRepo.Create(ctx, user); err != nil {
		return fmt.Errorf("failed to create user: %w", err)
	}

	return nil
}
