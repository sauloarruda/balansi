package cognito

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"errors"
	"fmt"
	"os"
	"testing"

	"services/auth/internal/config"
	apperrors "services/auth/internal/errors"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/cognitoidentityprovider"
	"github.com/aws/aws-sdk-go-v2/service/cognitoidentityprovider/types"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
)

// Helper functions to reduce code duplication

// testConfig creates a test configuration with optional overrides.
func testConfig(overrides ...func(*config.Config)) *config.Config {
	cfg := &config.Config{
		CognitoUserPoolID:   "test_pool",
		CognitoClientID:     "test_client_id",
		CognitoClientSecret: "",
		CognitoEndpoint:     "",
	}
	for _, override := range overrides {
		override(cfg)
	}
	return cfg
}

// localTestConfig creates a configuration for cognito-local integration tests.
// It reads from environment variables or uses default values from cognito-local setup.
func localTestConfig() *config.Config {
	// Try to get values from environment variables first (set by cognito-setup script)
	userPoolID := os.Getenv("COGNITO_USER_POOL_ID")
	if userPoolID == "" {
		// Default value from cognito-local setup (can be found in .cognito/db/)
		userPoolID = "local_6eLCsRav"
	}

	clientID := os.Getenv("COGNITO_CLIENT_ID")
	if clientID == "" {
		// Default value from cognito-local setup (can be found in .cognito/db/clients.json)
		clientID = "2qdfneigub7f5h79cnej0i3fo"
	}

	clientSecret := os.Getenv("COGNITO_CLIENT_SECRET")
	endpoint := os.Getenv("COGNITO_ENDPOINT")
	if endpoint == "" {
		endpoint = "http://localhost:9229"
	}

	return &config.Config{
		CognitoUserPoolID:   userPoolID,
		CognitoClientID:     clientID,
		CognitoClientSecret: clientSecret,
		CognitoEndpoint:     endpoint,
	}
}

// newTestClient creates a new client for testing, failing the test if creation fails.
func newTestClient(t *testing.T, cfg *config.Config) *Client {
	client, err := NewClient(cfg)
	require.NoError(t, err)
	return client
}

// assertArgumentError checks if an error is an ArgumentError with the expected argument name.
func assertArgumentError(t *testing.T, err error, expectedArgument string) {
	t.Helper()
	assert.Error(t, err)
	var argErr *apperrors.ArgumentError
	assert.True(t, errors.As(err, &argErr), "Error should be ArgumentError")
	assert.Equal(t, expectedArgument, argErr.Argument)
}

// mockCognitoClient is a mock implementation of cognitoClientInterface for testing.
type mockCognitoClient struct {
	mock.Mock
	SignUpFunc                 func(ctx context.Context, params *cognitoidentityprovider.SignUpInput, optFns ...func(*cognitoidentityprovider.Options)) (*cognitoidentityprovider.SignUpOutput, error)
	ListUsersFunc              func(ctx context.Context, params *cognitoidentityprovider.ListUsersInput, optFns ...func(*cognitoidentityprovider.Options)) (*cognitoidentityprovider.ListUsersOutput, error)
	AdminGetUserFunc           func(ctx context.Context, params *cognitoidentityprovider.AdminGetUserInput, optFns ...func(*cognitoidentityprovider.Options)) (*cognitoidentityprovider.AdminGetUserOutput, error)
	ResendConfirmationCodeFunc func(ctx context.Context, params *cognitoidentityprovider.ResendConfirmationCodeInput, optFns ...func(*cognitoidentityprovider.Options)) (*cognitoidentityprovider.ResendConfirmationCodeOutput, error)
	ConfirmSignUpFunc          func(ctx context.Context, params *cognitoidentityprovider.ConfirmSignUpInput, optFns ...func(*cognitoidentityprovider.Options)) (*cognitoidentityprovider.ConfirmSignUpOutput, error)
	InitiateAuthFunc           func(ctx context.Context, params *cognitoidentityprovider.InitiateAuthInput, optFns ...func(*cognitoidentityprovider.Options)) (*cognitoidentityprovider.InitiateAuthOutput, error)
}

func (m *mockCognitoClient) SignUp(ctx context.Context, params *cognitoidentityprovider.SignUpInput, optFns ...func(*cognitoidentityprovider.Options)) (*cognitoidentityprovider.SignUpOutput, error) {
	if m.SignUpFunc != nil {
		return m.SignUpFunc(ctx, params, optFns...)
	}
	args := m.Called(ctx, params)
	if args.Get(0) == nil {
		return nil, args.Error(1)
	}
	return args.Get(0).(*cognitoidentityprovider.SignUpOutput), args.Error(1)
}

func (m *mockCognitoClient) ListUsers(ctx context.Context, params *cognitoidentityprovider.ListUsersInput, optFns ...func(*cognitoidentityprovider.Options)) (*cognitoidentityprovider.ListUsersOutput, error) {
	if m.ListUsersFunc != nil {
		return m.ListUsersFunc(ctx, params, optFns...)
	}
	args := m.Called(ctx, params)
	if args.Get(0) == nil {
		return nil, args.Error(1)
	}
	return args.Get(0).(*cognitoidentityprovider.ListUsersOutput), args.Error(1)
}

func (m *mockCognitoClient) AdminGetUser(ctx context.Context, params *cognitoidentityprovider.AdminGetUserInput, optFns ...func(*cognitoidentityprovider.Options)) (*cognitoidentityprovider.AdminGetUserOutput, error) {
	args := m.Called(ctx, params)
	if args.Get(0) == nil {
		return nil, args.Error(1)
	}
	return args.Get(0).(*cognitoidentityprovider.AdminGetUserOutput), args.Error(1)
}

func (m *mockCognitoClient) ResendConfirmationCode(ctx context.Context, params *cognitoidentityprovider.ResendConfirmationCodeInput, optFns ...func(*cognitoidentityprovider.Options)) (*cognitoidentityprovider.ResendConfirmationCodeOutput, error) {
	if m.ResendConfirmationCodeFunc != nil {
		return m.ResendConfirmationCodeFunc(ctx, params, optFns...)
	}
	args := m.Called(ctx, params)
	if args.Get(0) == nil {
		return nil, args.Error(1)
	}
	return args.Get(0).(*cognitoidentityprovider.ResendConfirmationCodeOutput), args.Error(1)
}

func (m *mockCognitoClient) ConfirmSignUp(ctx context.Context, params *cognitoidentityprovider.ConfirmSignUpInput, optFns ...func(*cognitoidentityprovider.Options)) (*cognitoidentityprovider.ConfirmSignUpOutput, error) {
	if m.ConfirmSignUpFunc != nil {
		return m.ConfirmSignUpFunc(ctx, params, optFns...)
	}
	args := m.Called(ctx, params)
	if args.Get(0) == nil {
		return nil, args.Error(1)
	}
	return args.Get(0).(*cognitoidentityprovider.ConfirmSignUpOutput), args.Error(1)
}

func (m *mockCognitoClient) InitiateAuth(ctx context.Context, params *cognitoidentityprovider.InitiateAuthInput, optFns ...func(*cognitoidentityprovider.Options)) (*cognitoidentityprovider.InitiateAuthOutput, error) {
	if m.InitiateAuthFunc != nil {
		return m.InitiateAuthFunc(ctx, params, optFns...)
	}
	args := m.Called(ctx, params)
	if args.Get(0) == nil {
		return nil, args.Error(1)
	}
	return args.Get(0).(*cognitoidentityprovider.InitiateAuthOutput), args.Error(1)
}

// newClientWithMock creates a Client with a mocked AWS SDK client for testing.
func newClientWithMock(mockClient *mockCognitoClient, cfg *config.Config) *Client {
	return &Client{
		client:       mockClient,
		clientID:     cfg.CognitoClientID,
		clientSecret: cfg.CognitoClientSecret,
		userPoolID:   cfg.CognitoUserPoolID,
		endpoint:     cfg.CognitoEndpoint,
	}
}

// ============================================================================
// Tests for public methods (ordered by method definition in client.go)
// ============================================================================

// TestNewClient_Success tests successful client creation with different configurations.
func TestNewClient_Success(t *testing.T) {
	t.Run("with local endpoint", func(t *testing.T) {
		cfg := testConfig(func(c *config.Config) {
			c.CognitoUserPoolID = "local_test_pool"
			c.CognitoClientSecret = "test_secret"
			c.CognitoEndpoint = "http://localhost:9229"
		})

		client := newTestClient(t, cfg)
		assert.Equal(t, cfg.CognitoUserPoolID, client.userPoolID)
		assert.Equal(t, cfg.CognitoClientID, client.clientID)
		assert.Equal(t, cfg.CognitoEndpoint, client.endpoint)
	})

	t.Run("without endpoint", func(t *testing.T) {
		cfg := testConfig(func(c *config.Config) {
			c.CognitoClientSecret = "test_secret"
		})

		client := newTestClient(t, cfg)
		assert.Equal(t, cfg.CognitoUserPoolID, client.userPoolID)
		assert.Equal(t, cfg.CognitoClientID, client.clientID)
		assert.Equal(t, "", client.endpoint)
	})
}

// TestSignUp_Validation tests input validation for SignUp.
func TestSignUp_Validation(t *testing.T) {
	client := newTestClient(t, testConfig())
	ctx := context.Background()

	t.Run("empty email", func(t *testing.T) {
		_, err := client.SignUp(ctx, "", "Password123!", "Test User")
		assertArgumentError(t, err, "email")
	})

	t.Run("empty password", func(t *testing.T) {
		_, err := client.SignUp(ctx, "test@example.com", "", "Test User")
		assertArgumentError(t, err, "password")
	})

	t.Run("empty name", func(t *testing.T) {
		_, err := client.SignUp(ctx, "test@example.com", "Password123!", "")
		assertArgumentError(t, err, "name")
	})

	t.Run("all empty", func(t *testing.T) {
		_, err := client.SignUp(ctx, "", "", "")
		// Should return error for email first
		assertArgumentError(t, err, "email")
	})
}

// TestSignUp_Success tests successful signup with different configurations.
func TestSignUp_Success(t *testing.T) {
	tests := []struct {
		name         string
		configFn     func(*config.Config)
		validateHash bool
		useLocal     bool
	}{
		{
			name:         "without secret hash",
			configFn:     nil,
			validateHash: false,
			useLocal:     false,
		},
		{
			name: "with secret hash",
			configFn: func(c *config.Config) {
				c.CognitoClientSecret = "test_secret"
			},
			validateHash: true,
			useLocal:     false,
		},
		{
			name: "local endpoint uses email as username",
			configFn: func(c *config.Config) {
				c.CognitoEndpoint = "http://localhost:9229"
			},
			validateHash: false,
			useLocal:     true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			mockAWSClient := new(mockCognitoClient)
			var cfg *config.Config
			if tt.configFn != nil {
				cfg = testConfig(tt.configFn)
			} else {
				cfg = testConfig()
			}
			client := newClientWithMock(mockAWSClient, cfg)
			ctx := context.Background()

			email := "test@example.com"
			password := "TestPassword123!"
			name := "Test User"

			// Setup mock to return success
			mockAWSClient.On("SignUp", ctx, mock.MatchedBy(func(input *cognitoidentityprovider.SignUpInput) bool {
				valid := input != nil &&
					aws.ToString(input.ClientId) == cfg.CognitoClientID &&
					aws.ToString(input.Password) == password &&
					len(input.UserAttributes) >= 3

				// Check email attribute
				emailAttr := false
				for _, attr := range input.UserAttributes {
					if aws.ToString(attr.Name) == "email" && aws.ToString(attr.Value) == email {
						emailAttr = true
						break
					}
				}
				valid = valid && emailAttr

				// Check username based on endpoint
				if tt.useLocal {
					valid = valid && aws.ToString(input.Username) == email
				} else {
					// UUID format check (basic)
					username := aws.ToString(input.Username)
					valid = valid && len(username) > 0 && username != email
				}

				if tt.validateHash {
					valid = valid && input.SecretHash != nil && aws.ToString(input.SecretHash) != ""
				} else {
					valid = valid && input.SecretHash == nil
				}

				return valid
			})).Return(&cognitoidentityprovider.SignUpOutput{
				UserSub: aws.String("test-user-sub"),
			}, nil)

			// Execute
			username, err := client.SignUp(ctx, email, password, name)

			// Assert
			assert.NoError(t, err)
			assert.NotEmpty(t, username)
			// Now SignUp returns UserSub, not username
			assert.Equal(t, "test-user-sub", username, "SignUp should return UserSub")
			mockAWSClient.AssertExpectations(t)
		})
	}
}

// TestSignUp_Errors tests handling of various Cognito errors.
func TestSignUp_Errors(t *testing.T) {
	tests := []struct {
		name    string
		errType error
	}{
		{
			name:    "username exists",
			errType: &types.UsernameExistsException{Message: aws.String("An account with the given email already exists")},
		},
		{
			name:    "invalid password",
			errType: &types.InvalidPasswordException{Message: aws.String("Password did not conform with policy")},
		},
		{
			name:    "invalid parameter",
			errType: &types.InvalidParameterException{Message: aws.String("Invalid parameter")},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			mockAWSClient := new(mockCognitoClient)
			cfg := testConfig()
			client := newClientWithMock(mockAWSClient, cfg)
			ctx := context.Background()

			email := "test@example.com"
			password := "TestPassword123!"
			name := "Test User"

			// Setup mock to return error
			mockAWSClient.On("SignUp", ctx, mock.Anything).Return(nil, tt.errType)

			// Execute
			_, err := client.SignUp(ctx, email, password, name)

			// Assert
			assert.Error(t, err)
			assert.Contains(t, err.Error(), "cognito signup failed")
			mockAWSClient.AssertExpectations(t)
		})
	}
}

// TestIsUserConfirmed_Validation tests input validation for IsUserConfirmed.
func TestIsUserConfirmed_Validation(t *testing.T) {
	client := newTestClient(t, testConfig())
	ctx := context.Background()

	t.Run("empty email", func(t *testing.T) {
		_, _, _, err := client.IsUserConfirmed(ctx, "")
		assertArgumentError(t, err, "email")
	})
}

// TestIsUserConfirmed_Success tests successful user confirmation status checks.
func TestIsUserConfirmed_Success(t *testing.T) {
	tests := []struct {
		name            string
		userStatus      types.UserStatusType
		expectConfirmed bool
	}{
		{
			name:            "confirmed user",
			userStatus:      types.UserStatusTypeConfirmed,
			expectConfirmed: true,
		},
		{
			name:            "unconfirmed user",
			userStatus:      types.UserStatusTypeUnconfirmed,
			expectConfirmed: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			mockAWSClient := new(mockCognitoClient)
			cfg := testConfig()
			client := newClientWithMock(mockAWSClient, cfg)
			ctx := context.Background()

			email := "test@example.com"
			username := "test-username"
			userSub := "test-user-sub"

			// Setup mock to return user with sub attribute
			mockAWSClient.On("ListUsers", ctx, mock.MatchedBy(func(input *cognitoidentityprovider.ListUsersInput) bool {
				return input != nil &&
					aws.ToString(input.UserPoolId) == cfg.CognitoUserPoolID &&
					aws.ToString(input.Filter) == fmt.Sprintf("email = \"%s\"", email)
			})).Return(&cognitoidentityprovider.ListUsersOutput{
				Users: []types.UserType{
					{
						Username:   aws.String(username),
						UserStatus: tt.userStatus,
						Attributes: []types.AttributeType{
							{
								Name:  aws.String("sub"),
								Value: aws.String(userSub),
							},
						},
					},
				},
			}, nil)

			// Execute
			isConfirmed, retrievedUsername, cognitoID, err := client.IsUserConfirmed(ctx, email)

			// Assert
			assert.NoError(t, err)
			assert.Equal(t, tt.expectConfirmed, isConfirmed)
			assert.Equal(t, username, retrievedUsername)
			assert.Equal(t, userSub, cognitoID, "Should return UserSub, not username")
			mockAWSClient.AssertExpectations(t)
		})
	}
}

// TestIsUserConfirmed_FallbackToAdminGetUser tests the fallback to AdminGetUser when sub attribute is not in ListUsers response.
func TestIsUserConfirmed_FallbackToAdminGetUser(t *testing.T) {
	mockAWSClient := new(mockCognitoClient)
	cfg := testConfig()
	client := newClientWithMock(mockAWSClient, cfg)
	ctx := context.Background()

	email := "test@example.com"
	username := "test-username"
	userSub := "test-user-sub"

	// Setup mock: ListUsers returns user without sub attribute
	mockAWSClient.On("ListUsers", ctx, mock.MatchedBy(func(input *cognitoidentityprovider.ListUsersInput) bool {
		return input != nil &&
			aws.ToString(input.UserPoolId) == cfg.CognitoUserPoolID &&
			aws.ToString(input.Filter) == fmt.Sprintf("email = \"%s\"", email)
	})).Return(&cognitoidentityprovider.ListUsersOutput{
		Users: []types.UserType{
			{
				Username:   aws.String(username),
				UserStatus: types.UserStatusTypeConfirmed,
				// No Attributes - will trigger AdminGetUser fallback
			},
		},
	}, nil)

	// Setup mock: AdminGetUser returns user with sub attribute
	mockAWSClient.On("AdminGetUser", ctx, mock.MatchedBy(func(input *cognitoidentityprovider.AdminGetUserInput) bool {
		return input != nil &&
			aws.ToString(input.UserPoolId) == cfg.CognitoUserPoolID &&
			aws.ToString(input.Username) == username
	})).Return(&cognitoidentityprovider.AdminGetUserOutput{
		Username:   aws.String(username),
		UserStatus: types.UserStatusTypeConfirmed,
		UserAttributes: []types.AttributeType{
			{
				Name:  aws.String("sub"),
				Value: aws.String(userSub),
			},
		},
	}, nil)

	// Execute
	isConfirmed, retrievedUsername, cognitoID, err := client.IsUserConfirmed(ctx, email)

	// Assert
	assert.NoError(t, err)
	assert.True(t, isConfirmed)
	assert.Equal(t, username, retrievedUsername)
	assert.Equal(t, userSub, cognitoID, "Should return UserSub from AdminGetUser fallback")
	mockAWSClient.AssertExpectations(t)
}

// TestIsUserConfirmed_Errors tests handling of various errors.
func TestIsUserConfirmed_Errors(t *testing.T) {
	tests := []struct {
		name    string
		errType error
		users   []types.UserType
	}{
		{
			name:    "user not found",
			errType: nil,
			users:   []types.UserType{},
		},
		{
			name:    "list users error",
			errType: &types.InvalidParameterException{Message: aws.String("Invalid parameter")},
			users:   nil,
		},
		{
			name:    "empty username",
			errType: nil,
			users: []types.UserType{
				{
					Username:   nil,
					UserStatus: types.UserStatusTypeUnconfirmed,
				},
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			mockAWSClient := new(mockCognitoClient)
			cfg := testConfig()
			client := newClientWithMock(mockAWSClient, cfg)
			ctx := context.Background()

			email := "test@example.com"

			// Setup mock
			if tt.errType != nil {
				mockAWSClient.On("ListUsers", ctx, mock.Anything).Return(nil, tt.errType)
			} else {
				mockAWSClient.On("ListUsers", ctx, mock.Anything).Return(&cognitoidentityprovider.ListUsersOutput{
					Users: tt.users,
				}, nil)
			}

			// Execute
			_, _, _, err := client.IsUserConfirmed(ctx, email)

			// Assert
			assert.Error(t, err)
			mockAWSClient.AssertExpectations(t)
		})
	}
}

// TestResendConfirmationCode_Validation tests input validation for ResendConfirmationCode.
func TestResendConfirmationCode_Validation(t *testing.T) {
	client := newTestClient(t, testConfig())
	ctx := context.Background()

	t.Run("empty username", func(t *testing.T) {
		err := client.ResendConfirmationCode(ctx, "")
		assertArgumentError(t, err, "username")
	})
}

// TestResendConfirmationCode_Success tests successful resend confirmation code.
func TestResendConfirmationCode_Success(t *testing.T) {
	tests := []struct {
		name         string
		configFn     func(*config.Config)
		validateHash bool
		isLocal      bool
	}{
		{
			name:         "without secret hash",
			configFn:     nil,
			validateHash: false,
			isLocal:      false,
		},
		{
			name: "with secret hash",
			configFn: func(c *config.Config) {
				c.CognitoClientSecret = "test_secret"
			},
			validateHash: true,
			isLocal:      false,
		},
		{
			name: "local endpoint returns nil",
			configFn: func(c *config.Config) {
				c.CognitoEndpoint = "http://localhost:9229"
			},
			validateHash: false,
			isLocal:      true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			mockAWSClient := new(mockCognitoClient)
			var cfg *config.Config
			if tt.configFn != nil {
				cfg = testConfig(tt.configFn)
			} else {
				cfg = testConfig()
			}
			client := newClientWithMock(mockAWSClient, cfg)
			ctx := context.Background()

			username := "test@example.com"

			if tt.isLocal {
				// Local endpoint doesn't call the API
				err := client.ResendConfirmationCode(ctx, username)
				assert.NoError(t, err)
				mockAWSClient.AssertNotCalled(t, "ResendConfirmationCode")
			} else {
				// Setup mock to return success
				mockAWSClient.On("ResendConfirmationCode", ctx, mock.MatchedBy(func(input *cognitoidentityprovider.ResendConfirmationCodeInput) bool {
					valid := input != nil &&
						aws.ToString(input.ClientId) == cfg.CognitoClientID &&
						aws.ToString(input.Username) == username

					if tt.validateHash {
						valid = valid && input.SecretHash != nil && aws.ToString(input.SecretHash) != ""
					} else {
						valid = valid && input.SecretHash == nil
					}

					return valid
				})).Return(&cognitoidentityprovider.ResendConfirmationCodeOutput{}, nil)

				// Execute
				err := client.ResendConfirmationCode(ctx, username)

				// Assert
				assert.NoError(t, err)
				mockAWSClient.AssertExpectations(t)
			}
		})
	}
}

// TestResendConfirmationCode_Errors tests handling of various errors.
func TestResendConfirmationCode_Errors(t *testing.T) {
	tests := []struct {
		name    string
		errType error
	}{
		{
			name:    "user not found",
			errType: &types.UserNotFoundException{Message: aws.String("User does not exist")},
		},
		{
			name:    "invalid parameter",
			errType: &types.InvalidParameterException{Message: aws.String("Invalid parameter")},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			mockAWSClient := new(mockCognitoClient)
			cfg := testConfig()
			client := newClientWithMock(mockAWSClient, cfg)
			ctx := context.Background()

			username := "test@example.com"

			// Setup mock to return error
			mockAWSClient.On("ResendConfirmationCode", ctx, mock.Anything).Return(nil, tt.errType)

			// Execute
			err := client.ResendConfirmationCode(ctx, username)

			// Assert
			assert.Error(t, err)
			assert.Contains(t, err.Error(), "failed to resend confirmation code")
			mockAWSClient.AssertExpectations(t)
		})
	}
}

// TestConfirmSignUp_Validation tests input validation for ConfirmSignUp.
func TestConfirmSignUp_Validation(t *testing.T) {
	client := newTestClient(t, testConfig())
	ctx := context.Background()

	t.Run("empty cognitoId", func(t *testing.T) {
		err := client.ConfirmSignUp(ctx, "", "123456")
		assertArgumentError(t, err, "cognitoId")
	})

	t.Run("empty confirmationCode", func(t *testing.T) {
		err := client.ConfirmSignUp(ctx, "test-user-sub", "")
		assertArgumentError(t, err, "confirmationCode")
	})

	t.Run("both empty", func(t *testing.T) {
		err := client.ConfirmSignUp(ctx, "", "")
		// Should return error for cognitoId first
		assertArgumentError(t, err, "cognitoId")
	})
}

// TestConfirmSignUp_Success tests successful confirmation with different configurations.
func TestConfirmSignUp_Success(t *testing.T) {
	tests := []struct {
		name         string
		configFn     func(*config.Config)
		validateHash bool
	}{
		{
			name:         "without secret hash",
			configFn:     nil,
			validateHash: false,
		},
		{
			name: "with secret hash",
			configFn: func(c *config.Config) {
				c.CognitoClientSecret = "test_secret"
			},
			validateHash: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			mockAWSClient := new(mockCognitoClient)
			var cfg *config.Config
			if tt.configFn != nil {
				cfg = testConfig(tt.configFn)
			} else {
				cfg = testConfig()
			}
			client := newClientWithMock(mockAWSClient, cfg)
			ctx := context.Background()

			userSub := "test-user-sub"
			username := "test-username-uuid" // AWS Cognito uses UUID as username
			confirmationCode := "123456"

			// No ListUsers mock needed - username is passed directly to ConfirmSignUp
			// Setup mock: ConfirmSignUp to confirm with username
			mockAWSClient.On("ConfirmSignUp", ctx, mock.MatchedBy(func(input *cognitoidentityprovider.ConfirmSignUpInput) bool {
				valid := input != nil &&
					aws.ToString(input.ClientId) == cfg.CognitoClientID &&
					aws.ToString(input.Username) == username &&
					aws.ToString(input.ConfirmationCode) == confirmationCode

				if tt.validateHash {
					valid = valid && input.SecretHash != nil && aws.ToString(input.SecretHash) != ""
				} else {
					valid = valid && input.SecretHash == nil
				}

				return valid
			})).Return(&cognitoidentityprovider.ConfirmSignUpOutput{}, nil)

			// Execute (pass username directly to avoid ListUsers call in ConfirmSignUp)
			err := client.ConfirmSignUp(ctx, userSub, confirmationCode, username)

			// Assert
			assert.NoError(t, err)
			mockAWSClient.AssertExpectations(t)
		})
	}
}

// TestConfirmSignUp_Errors tests handling of various Cognito errors.
func TestConfirmSignUp_Errors(t *testing.T) {
	tests := []struct {
		name        string
		errType     error
		description string
	}{
		{
			name:        "code mismatch",
			errType:     &types.CodeMismatchException{Message: aws.String("Invalid verification code provided")},
			description: "invalid confirmation code",
		},
		{
			name:        "expired code",
			errType:     &types.ExpiredCodeException{Message: aws.String("Invalid code provided, please request a code again")},
			description: "expired confirmation code",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			mockAWSClient := new(mockCognitoClient)
			cfg := testConfig()
			client := newClientWithMock(mockAWSClient, cfg)
			ctx := context.Background()

			userSub := "test-user-sub"
			username := "test-username-uuid" // AWS Cognito uses UUID as username
			confirmationCode := "123456"

			// No ListUsers mock needed - username is passed directly to ConfirmSignUp
			// Setup mock: ConfirmSignUp to return error
			mockAWSClient.On("ConfirmSignUp", ctx, mock.MatchedBy(func(input *cognitoidentityprovider.ConfirmSignUpInput) bool {
				return input != nil &&
					aws.ToString(input.ClientId) == cfg.CognitoClientID &&
					aws.ToString(input.Username) == username &&
					aws.ToString(input.ConfirmationCode) == confirmationCode
			})).Return(nil, tt.errType)

			// Execute (pass username directly to avoid ListUsers call in ConfirmSignUp)
			err := client.ConfirmSignUp(ctx, userSub, confirmationCode, username)

			// Assert
			assert.Error(t, err)
			assert.Contains(t, err.Error(), "failed to validate confirmation code")
			mockAWSClient.AssertExpectations(t)
		})
	}
}

// ============================================================================
// Tests for private/helper methods
// ============================================================================

// TestCalculateSecretHash_Success tests successful secret hash calculation with different inputs.
func TestCalculateSecretHash_Success(t *testing.T) {
	tests := []struct {
		name         string
		username     string
		clientID     string
		clientSecret string
		wantLength   int
	}{
		{
			name:         "basic hash",
			username:     "testuser",
			clientID:     "testclient",
			clientSecret: "testsecret",
			wantLength:   44, // base64 encoded HMAC-SHA256 is 44 chars
		},
		{
			name:         "email as username",
			username:     "user@example.com",
			clientID:     "client123",
			clientSecret: "secret123",
			wantLength:   44,
		},
		{
			name:         "empty strings",
			username:     "",
			clientID:     "",
			clientSecret: "",
			wantLength:   44,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			hash := calculateSecretHash(tt.username, tt.clientID, tt.clientSecret)
			assert.Len(t, hash, tt.wantLength, "Secret hash should have correct length")

			// Verify it's valid base64
			_, err := base64.StdEncoding.DecodeString(hash)
			assert.NoError(t, err, "Secret hash should be valid base64")

			// Verify it's deterministic
			hash2 := calculateSecretHash(tt.username, tt.clientID, tt.clientSecret)
			assert.Equal(t, hash, hash2, "Secret hash should be deterministic")
		})
	}
}

// TestCalculateSecretHash_Algorithm tests that our implementation matches the expected HMAC-SHA256 calculation.
func TestCalculateSecretHash_Algorithm(t *testing.T) {
	username := "testuser"
	clientID := "testclient"
	clientSecret := "testsecret"

	hash := calculateSecretHash(username, clientID, clientSecret)

	// Manually calculate expected hash
	message := username + clientID
	mac := hmac.New(sha256.New, []byte(clientSecret))
	mac.Write([]byte(message))
	expectedHash := base64.StdEncoding.EncodeToString(mac.Sum(nil))

	assert.Equal(t, expectedHash, hash, "Secret hash should match manual calculation")
}
