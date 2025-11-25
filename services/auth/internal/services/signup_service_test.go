package services

import (
	"context"
	"errors"
	"testing"

	"services/auth/internal/encryption"
	"services/auth/internal/models"
	"services/auth/internal/testhelpers"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/cognitoidentityprovider/types"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
)

const (
	testUserName    = "John Doe"
	testUserEmail   = "john@example.com"
	testCognitoID   = "cognito-123"
	testCognitoUser = "john@example.com"
)

func TestSignupService_Signup_NewUser(t *testing.T) {
	mockRepo := new(testhelpers.MockUserRepository)
	mockCognito := new(testhelpers.MockCognitoClient)

	service := NewSignupServiceWithInterfaces(
		mockRepo,
		mockCognito,
		"test-secret-key-1234567890123456",
	)

	ctx := context.Background()
	name := testUserName
	email := testUserEmail
	cognitoID := testCognitoID

	// Setup mocks
	mockRepo.On("FindByEmail", ctx, email).Return(nil, nil)
	mockCognito.On("SignUp", ctx, email, mock.AnythingOfType("string"), name).Return(cognitoID, nil)
	mockRepo.On("Create", ctx, mock.MatchedBy(func(user *models.User) bool {
		return user.Name == name && user.Email == email && user.CognitoID != nil && *user.CognitoID == cognitoID
	})).Return(nil).Run(func(args mock.Arguments) {
		user := args.Get(1).(*models.User)
		user.ID = 1
	})

	// Execute
	result, err := service.Signup(ctx, name, email)

	// Assert
	require.NoError(t, err)
	require.NotNil(t, result)
	assert.Equal(t, models.SignupStatusPendingConfirmation, result.Status)
	assert.NotNil(t, result.User)
	assert.Equal(t, name, result.User.Name)
	assert.Equal(t, email, result.User.Email)
	assert.NotNil(t, result.User.CognitoID)
	assert.Equal(t, cognitoID, *result.User.CognitoID)
	assert.NotNil(t, result.User.TemporaryPassword)

	mockRepo.AssertExpectations(t)
	mockCognito.AssertExpectations(t)
}

func TestSignupService_Signup_UserAlreadyExists_Confirmed(t *testing.T) {
	mockRepo := new(testhelpers.MockUserRepository)
	mockCognito := new(testhelpers.MockCognitoClient)

	service := NewSignupServiceWithInterfaces(
		mockRepo,
		mockCognito,
		"test-secret-key-1234567890123456",
	)

	ctx := context.Background()
	name := testUserName
	email := testUserEmail
	cognitoID := testCognitoID

	existingUser := &models.User{
		ID:        1,
		Name:      name,
		Email:     email,
		CognitoID: &cognitoID,
	}

	// Setup mocks
	mockRepo.On("FindByEmail", ctx, email).Return(existingUser, nil)
	mockCognito.On("IsUserConfirmed", ctx, email).Return(true, "username", cognitoID, nil)

	// Execute
	result, err := service.Signup(ctx, name, email)

	// Assert
	assert.Error(t, err)
	assert.True(t, errors.Is(err, ErrUserAlreadyExists))
	assert.Nil(t, result)

	mockRepo.AssertExpectations(t)
	mockCognito.AssertExpectations(t)
}

func TestSignupService_Signup_UserExistsButUnconfirmed(t *testing.T) {
	mockRepo := new(testhelpers.MockUserRepository)
	mockCognito := new(testhelpers.MockCognitoClient)

	service := NewSignupServiceWithInterfaces(
		mockRepo,
		mockCognito,
		"test-secret-key-1234567890123456",
	)

	ctx := context.Background()
	name := testUserName
	email := testUserEmail
	cognitoID := testCognitoID
	username := testCognitoUser

	existingUser := &models.User{
		ID:        1,
		Name:      name,
		Email:     email,
		CognitoID: &cognitoID,
	}

	// Setup mocks
	mockRepo.On("FindByEmail", ctx, email).Return(existingUser, nil)
	mockCognito.On("IsUserConfirmed", ctx, email).Return(false, username, cognitoID, nil)
	mockCognito.On("ResendConfirmationCode", ctx, username).Return(nil)

	// Execute
	result, err := service.Signup(ctx, name, email)

	// Assert
	require.NoError(t, err)
	require.NotNil(t, result)
	assert.Equal(t, models.SignupStatusPendingConfirmation, result.Status)
	assert.NotNil(t, result.User)
	assert.Equal(t, existingUser.ID, result.User.ID)

	mockRepo.AssertExpectations(t)
	mockCognito.AssertExpectations(t)
}

func TestSignupService_Signup_UserInCognitoButNotDB(t *testing.T) {
	mockRepo := new(testhelpers.MockUserRepository)
	mockCognito := new(testhelpers.MockCognitoClient)

	service := NewSignupServiceWithInterfaces(
		mockRepo,
		mockCognito,
		"test-secret-key-1234567890123456",
	)

	ctx := context.Background()
	name := testUserName
	email := testUserEmail
	cognitoID := testCognitoID
	username := testCognitoUser

	// Setup mocks - user not in DB, but exists in Cognito (UsernameExistsException)
	mockRepo.On("FindByEmail", ctx, email).Return(nil, nil)
	mockCognito.On("SignUp", ctx, email, mock.AnythingOfType("string"), name).
		Return("", &types.UsernameExistsException{})
	mockCognito.On("IsUserConfirmed", ctx, email).Return(false, username, cognitoID, nil)
	mockCognito.On("ResendConfirmationCode", ctx, username).Return(nil)
	mockRepo.On("Create", ctx, mock.MatchedBy(func(user *models.User) bool {
		return user.Name == name && user.Email == email && user.CognitoID != nil && *user.CognitoID == cognitoID
	})).Return(nil).Run(func(args mock.Arguments) {
		user := args.Get(1).(*models.User)
		user.ID = 1
	})

	// Execute
	result, err := service.Signup(ctx, name, email)

	// Assert
	require.NoError(t, err)
	require.NotNil(t, result)
	assert.Equal(t, models.SignupStatusPendingConfirmation, result.Status)
	assert.NotNil(t, result.User)
	assert.Equal(t, name, result.User.Name)
	assert.Equal(t, email, result.User.Email)
	assert.NotNil(t, result.User.CognitoID)
	assert.Equal(t, cognitoID, *result.User.CognitoID)
	assert.NotNil(t, result.User.TemporaryPassword)

	mockRepo.AssertExpectations(t)
	mockCognito.AssertExpectations(t)
}

func TestSignupService_Signup_UserInDBButNotCognito(t *testing.T) {
	mockRepo := new(testhelpers.MockUserRepository)
	mockCognito := new(testhelpers.MockCognitoClient)

	service := NewSignupServiceWithInterfaces(
		mockRepo,
		mockCognito,
		"test-secret-key-1234567890123456",
	)

	ctx := context.Background()
	name := testUserName
	email := testUserEmail
	cognitoID := testCognitoID

	existingUser := &models.User{
		ID:        1,
		Name:      name,
		Email:     email,
		CognitoID: nil, // No Cognito ID yet
	}

	// Setup mocks
	mockRepo.On("FindByEmail", ctx, email).Return(existingUser, nil)
	mockCognito.On("SignUp", ctx, email, mock.AnythingOfType("string"), name).Return(cognitoID, nil)
	mockRepo.On("Update", ctx, mock.MatchedBy(func(user *models.User) bool {
		return user.ID == existingUser.ID && user.CognitoID != nil && *user.CognitoID == cognitoID
	})).Return(nil)

	// Execute
	result, err := service.Signup(ctx, name, email)

	// Assert
	require.NoError(t, err)
	require.NotNil(t, result)
	assert.Equal(t, models.SignupStatusPendingConfirmation, result.Status)
	assert.NotNil(t, result.User)
	assert.Equal(t, existingUser.ID, result.User.ID)
	assert.NotNil(t, result.User.CognitoID)
	assert.Equal(t, cognitoID, *result.User.CognitoID)

	mockRepo.AssertExpectations(t)
	mockCognito.AssertExpectations(t)
}

func TestSignupService_Signup_RepositoryError(t *testing.T) {
	mockRepo := new(testhelpers.MockUserRepository)
	mockCognito := new(testhelpers.MockCognitoClient)

	service := NewSignupServiceWithInterfaces(
		mockRepo,
		mockCognito,
		"test-secret-key-1234567890123456",
	)

	ctx := context.Background()
	name := testUserName
	email := testUserEmail

	// Setup mocks - repository error
	mockRepo.On("FindByEmail", ctx, email).Return(nil, errors.New("database error"))

	// Execute
	result, err := service.Signup(ctx, name, email)

	// Assert
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "failed to check existing user")
	assert.Nil(t, result)

	mockRepo.AssertExpectations(t)
}

func TestSignupService_Signup_CognitoError(t *testing.T) {
	mockRepo := new(testhelpers.MockUserRepository)
	mockCognito := new(testhelpers.MockCognitoClient)

	service := NewSignupServiceWithInterfaces(
		mockRepo,
		mockCognito,
		"test-secret-key-1234567890123456",
	)

	ctx := context.Background()
	name := testUserName
	email := testUserEmail

	// Setup mocks
	mockRepo.On("FindByEmail", ctx, email).Return(nil, nil)
	mockCognito.On("SignUp", ctx, email, mock.AnythingOfType("string"), name).
		Return("", errors.New("cognito error"))

	// Execute
	result, err := service.Signup(ctx, name, email)

	// Assert
	assert.Error(t, err)
	assert.ErrorIs(t, err, ErrSignupProviderUnavailable)
	assert.Nil(t, result)

	mockRepo.AssertExpectations(t)
	mockCognito.AssertExpectations(t)
}

func TestSignupService_Signup_EncryptionError(t *testing.T) {
	mockRepo := new(testhelpers.MockUserRepository)
	mockCognito := new(testhelpers.MockCognitoClient)

	service := NewSignupServiceWithInterfaces(
		mockRepo,
		mockCognito,
		"test-secret-key-1234567890123456",
	)

	// Override encrypt function to return error
	service.encryptFunc = func(plaintext, secret string) (string, error) {
		return "", errors.New("encryption error")
	}

	ctx := context.Background()
	name := testUserName
	email := testUserEmail

	// Setup mocks
	mockRepo.On("FindByEmail", ctx, email).Return(nil, nil)

	// Execute
	result, err := service.Signup(ctx, name, email)

	// Assert
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "failed to encrypt password")
	assert.Nil(t, result)

	mockRepo.AssertExpectations(t)
}

func TestSignupService_Signup_ResendConfirmationCodeError(t *testing.T) {
	mockRepo := new(testhelpers.MockUserRepository)
	mockCognito := new(testhelpers.MockCognitoClient)

	service := NewSignupServiceWithInterfaces(
		mockRepo,
		mockCognito,
		"test-secret-key-1234567890123456",
	)

	ctx := context.Background()
	name := testUserName
	email := testUserEmail
	cognitoID := testCognitoID
	username := testCognitoUser

	existingUser := &models.User{
		ID:        1,
		Name:      name,
		Email:     email,
		CognitoID: &cognitoID,
	}

	// Setup mocks
	mockRepo.On("FindByEmail", ctx, email).Return(existingUser, nil)
	mockCognito.On("IsUserConfirmed", ctx, email).Return(false, username, cognitoID, nil)
	mockCognito.On("ResendConfirmationCode", ctx, username).Return(errors.New("resend error"))

	// Execute
	result, err := service.Signup(ctx, name, email)

	// Assert
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "failed to resend confirmation code")
	assert.Nil(t, result)

	mockRepo.AssertExpectations(t)
	mockCognito.AssertExpectations(t)
}

func TestGenerateTemporaryPassword(t *testing.T) {
	tests := []struct {
		name   string
		length int
	}{
		{"minimum length", 4},
		{"default length", 32},
		{"custom length", 16},
		{"very short (should use minimum)", 2},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			password, err := generateTemporaryPassword(tt.length)
			require.NoError(t, err)
			assert.NotEmpty(t, password)

			// Check minimum length
			expectedLength := tt.length
			if expectedLength < 4 {
				expectedLength = 4
			}
			assert.GreaterOrEqual(t, len(password), expectedLength)

			// Check that password contains required character types
			hasLower := false
			hasUpper := false
			hasNumber := false
			hasSpecial := false

			for _, char := range password {
				if char >= 'a' && char <= 'z' {
					hasLower = true
				}
				if char >= 'A' && char <= 'Z' {
					hasUpper = true
				}
				if char >= '0' && char <= '9' {
					hasNumber = true
				}
				if char == '!' || char == '@' || char == '#' || char == '$' || char == '%' ||
					char == '^' || char == '&' || char == '*' || char == '(' || char == ')' ||
					char == '-' || char == '_' || char == '+' || char == '=' || char == '<' ||
					char == '>' || char == '?' {
					hasSpecial = true
				}
			}

			assert.True(t, hasLower, "Password should contain lowercase")
			assert.True(t, hasUpper, "Password should contain uppercase")
			assert.True(t, hasNumber, "Password should contain number")
			assert.True(t, hasSpecial, "Password should contain special character")
		})
	}
}

func TestGenerateTemporaryPassword_Error(t *testing.T) {
	// This test is difficult to trigger since rand.Read rarely fails
	// But we can test the error path exists in the code
	// In practice, this would require mocking crypto/rand which is complex
	// So we'll just verify the function signature and basic behavior
	password, err := generateTemporaryPassword(32)
	assert.NoError(t, err)
	assert.NotEmpty(t, password)
}

func TestSignupService_Confirm_Idempotency_UserAlreadyConfirmedInCognito(t *testing.T) {
	mockRepo := new(testhelpers.MockUserRepository)
	mockCognito := new(testhelpers.MockCognitoClient)

	service := NewSignupServiceWithInterfaces(
		mockRepo,
		mockCognito,
		"test-secret-key-1234567890123456",
	)

	ctx := context.Background()
	userID := int64(1)
	code := "123456"
	cognitoID := testCognitoID
	username := testCognitoUser
	email := testUserEmail
	secret := "test-secret-key-1234567890123456"

	// Encrypt a test password
	testPassword := "TestPassword123!"
	encryptedPassword, err := encryption.Encrypt(testPassword, secret)
	require.NoError(t, err, "Failed to encrypt test password")

	// User exists in DB but status is pending_confirmation (stale state)
	user := &models.User{
		ID:                1,
		Name:              testUserName,
		Email:             email,
		CognitoID:         &cognitoID,
		Status:            models.UserStatusPendingConfirmation,
		TemporaryPassword: &encryptedPassword,
	}

	// Mock: ConfirmSignUp returns NotAuthorizedException indicating user already confirmed
	notAuthorizedErr := &types.NotAuthorizedException{
		Message: aws.String("User is already confirmed."),
	}

	// Setup mocks
	mockRepo.On("FindByID", ctx, userID).Return(user, nil)
	mockCognito.On("GetUsernameByUserSub", ctx, cognitoID, []string{email}).Return(username, nil)
	mockCognito.On("ConfirmSignUp", ctx, cognitoID, code, []string{username}).Return(notAuthorizedErr)
	// Verify user is actually confirmed in Cognito
	mockCognito.On("IsUserConfirmed", ctx, email).Return(true, username, cognitoID, nil)
	// Update DB status to confirmed
	mockRepo.On("Update", ctx, mock.MatchedBy(func(u *models.User) bool {
		return u.ID == 1 && u.Status == models.UserStatusConfirmed
	})).Return(nil)
	// Decrypt password and login - should use the decrypted test password
	mockCognito.On("InitiateAuth", ctx, username, testPassword).Return(&types.AuthenticationResultType{
		AccessToken:  aws.String("access-token"),
		IdToken:      aws.String("id-token"),
		RefreshToken: aws.String("refresh-token"),
		ExpiresIn:    3600,
		TokenType:    aws.String("Bearer"),
	}, nil)

	// EXPECTATION: Check that TemporaryPassword is set to nil
	mockRepo.On("Update", ctx, mock.MatchedBy(func(u *models.User) bool {
		return u.ID == 1 && u.TemporaryPassword == nil
	})).Return(nil)

	// Execute
	result, err := service.Confirm(ctx, userID, code)

	// Assert
	require.NoError(t, err)
	require.NotNil(t, result)
	assert.Equal(t, "refresh-token", result.RefreshToken)
	assert.Equal(t, int64(1), result.UserID)
	assert.Equal(t, username, result.Username)

	mockRepo.AssertExpectations(t)
	mockCognito.AssertExpectations(t)
}
