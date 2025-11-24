package cognito

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"errors"
	"fmt"
	"services/auth/internal/config"
	apperrors "services/auth/internal/errors"
	"services/auth/internal/logger"
	"strings"

	"github.com/aws/aws-sdk-go-v2/aws"
	awsconfig "github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/credentials"
	"github.com/aws/aws-sdk-go-v2/service/cognitoidentityprovider"
	"github.com/aws/aws-sdk-go-v2/service/cognitoidentityprovider/types"
	"github.com/google/uuid"
)

// cognitoClientInterface defines the interface for Cognito Identity Provider operations.
// This allows us to mock the AWS SDK client in tests.
type cognitoClientInterface interface {
	SignUp(ctx context.Context, params *cognitoidentityprovider.SignUpInput, optFns ...func(*cognitoidentityprovider.Options)) (*cognitoidentityprovider.SignUpOutput, error)
	ListUsers(ctx context.Context, params *cognitoidentityprovider.ListUsersInput, optFns ...func(*cognitoidentityprovider.Options)) (*cognitoidentityprovider.ListUsersOutput, error)
	AdminGetUser(ctx context.Context, params *cognitoidentityprovider.AdminGetUserInput, optFns ...func(*cognitoidentityprovider.Options)) (*cognitoidentityprovider.AdminGetUserOutput, error)
	ResendConfirmationCode(ctx context.Context, params *cognitoidentityprovider.ResendConfirmationCodeInput, optFns ...func(*cognitoidentityprovider.Options)) (*cognitoidentityprovider.ResendConfirmationCodeOutput, error)
	ConfirmSignUp(ctx context.Context, params *cognitoidentityprovider.ConfirmSignUpInput, optFns ...func(*cognitoidentityprovider.Options)) (*cognitoidentityprovider.ConfirmSignUpOutput, error)
	InitiateAuth(ctx context.Context, params *cognitoidentityprovider.InitiateAuthInput, optFns ...func(*cognitoidentityprovider.Options)) (*cognitoidentityprovider.InitiateAuthOutput, error)
}

type Client struct {
	client       cognitoClientInterface
	clientID     string
	clientSecret string
	userPoolID   string
	endpoint     string // Store endpoint to detect local vs AWS
}

// isLocalEndpoint checks if the client is configured to use cognito-local (localhost:9229).
// This is useful for determining behavior differences between local development and AWS Cognito.
func (c *Client) isLocalEndpoint() bool {
	return c.endpoint != "" && strings.Contains(c.endpoint, "localhost:9229")
}

// calculateSecretHash calculates the SECRET_HASH for Cognito API calls
// SECRET_HASH = HMAC_SHA256(username + clientId, clientSecret).
func calculateSecretHash(username, clientID, clientSecret string) string {
	message := username + clientID
	mac := hmac.New(sha256.New, []byte(clientSecret))
	mac.Write([]byte(message))
	return base64.StdEncoding.EncodeToString(mac.Sum(nil))
}

// getSecretHash returns the SECRET_HASH for the given username if client secret is configured.
// Returns nil if no client secret is configured.
func (c *Client) getSecretHash(username string) *string {
	if c.clientSecret == "" {
		return nil
	}
	secretHash := calculateSecretHash(username, c.clientID, c.clientSecret)
	return aws.String(secretHash)
}

func NewClient(cfg *config.Config) (*Client, error) {
	opts := []func(*awsconfig.LoadOptions) error{
		awsconfig.WithRegion("us-east-2"), // Default region, can be overridden by env
	}

	// Use dummy credentials for cognito-local/LocalStack
	if cfg.CognitoEndpoint != "" {
		opts = append(opts, awsconfig.WithCredentialsProvider(
			credentials.NewStaticCredentialsProvider("test", "test", ""),
		))
	}

	awsCfg, err := awsconfig.LoadDefaultConfig(context.TODO(), opts...)
	if err != nil {
		return nil, err
	}

	// Configure custom endpoint using BaseEndpoint (modern approach, replaces deprecated WithEndpointResolverWithOptions)
	clientOpts := []func(*cognitoidentityprovider.Options){}
	if cfg.CognitoEndpoint != "" {
		logger.Info("Configuring Cognito client with custom endpoint: %s", cfg.CognitoEndpoint)
		clientOpts = append(clientOpts, func(o *cognitoidentityprovider.Options) {
			o.BaseEndpoint = aws.String(cfg.CognitoEndpoint)
		})
	}

	client := cognitoidentityprovider.NewFromConfig(awsCfg, clientOpts...)

	logger.Info("Cognito client initialized - UserPoolID: %s, ClientID: %s, Endpoint: %s",
		cfg.CognitoUserPoolID, cfg.CognitoClientID, cfg.CognitoEndpoint)

	return &Client{
		client:       client,
		clientID:     cfg.CognitoClientID,
		clientSecret: cfg.CognitoClientSecret,
		userPoolID:   cfg.CognitoUserPoolID,
		endpoint:     cfg.CognitoEndpoint,
	}, nil
}

func (c *Client) SignUp(ctx context.Context, email, password, name string) (string, error) {
	// Validate input parameters
	if email == "" {
		return "", apperrors.NewArgumentError("email", "cannot be empty")
	}
	if password == "" {
		return "", apperrors.NewArgumentError("password", "cannot be empty")
	}
	if name == "" {
		return "", apperrors.NewArgumentError("name", "cannot be empty")
	}

	// Determine username based on endpoint configuration
	// - For cognito-local (endpoint contains localhost:9229): use email as username
	// - For AWS Cognito with email alias: use UUID (AWS doesn't allow email format when email is alias)
	var username string
	if c.isLocalEndpoint() {
		// cognito-local requires email as username
		username = email
		logger.Debug("Using email as username for cognito-local")
	} else {
		// AWS Cognito with email alias requires UUID as username
		username = uuid.New().String()
		logger.Debug("Using UUID as username for AWS Cognito")
	}

	input := &cognitoidentityprovider.SignUpInput{
		ClientId:   aws.String(c.clientID),
		Username:   aws.String(username),
		Password:   aws.String(password),
		SecretHash: c.getSecretHash(username),
		UserAttributes: []types.AttributeType{
			{Name: aws.String("email"), Value: aws.String(email)},
			{Name: aws.String("name"), Value: aws.String(name)},
			{Name: aws.String("nickname"), Value: aws.String(name)},
		},
	}

	logger.Info("Calling Cognito SignUp - Email: %s, ClientID: %s, UserPoolID: %s",
		email, c.clientID, c.userPoolID)
	logger.DebugJSON("SignUp Input", input)

	output, err := c.client.SignUp(ctx, input)
	if err != nil {
		logger.Error("Cognito SignUp error: %v", err)
		logger.DebugJSON("SignUp Error", err)
		return "", fmt.Errorf("cognito signup failed: %w", err)
	}

	logger.DebugJSON("SignUp Output", output)

	if output.UserSub == nil {
		logger.Error("Cognito SignUp returned nil UserSub")
		return "", errors.New("cognito signup did not return user sub")
	}

	logger.Info("Cognito SignUp successful - Username: %s, UserSub: %s", username, *output.UserSub)
	// Return UserSub (internal Cognito ID) instead of username
	return *output.UserSub, nil
}

// IsUserConfirmed checks if a user is confirmed in Cognito
// It tries to find the user by email and checks their status
// Returns: isConfirmed, username, cognitoId (UserSub to be stored), error.
// The cognitoId returned is the UserSub (internal Cognito ID), which is what we store in the database.
func (c *Client) IsUserConfirmed(ctx context.Context, email string) (bool, string, string, error) {
	// Validate input parameters
	if email == "" {
		return false, "", "", apperrors.NewArgumentError("email", "cannot be empty")
	}

	// First, try to find the user by listing users with the email attribute
	// We'll search for users with matching email
	input := &cognitoidentityprovider.ListUsersInput{
		UserPoolId: aws.String(c.userPoolID),
		Filter:     aws.String(fmt.Sprintf("email = \"%s\"", email)),
		Limit:      aws.Int32(1),
	}

	logger.DebugJSON("ListUsers Input", input)

	output, err := c.client.ListUsers(ctx, input)
	if err != nil {
		logger.Error("Error listing users: %v", err)
		logger.DebugJSON("ListUsers Error", err)
		return false, "", "", fmt.Errorf("failed to list users: %w", err)
	}

	logger.DebugJSON("ListUsers Output", output)

	if len(output.Users) == 0 {
		return false, "", "", errors.New("user not found")
	}

	user := output.Users[0]
	username := ""
	if user.Username != nil {
		username = *user.Username
	}

	if username == "" {
		return false, "", "", errors.New("user found but username is empty")
	}

	// Get UserSub (internal Cognito ID) from attributes
	// The 'sub' attribute contains the UserSub
	userSub := ""
	if user.Attributes != nil {
		for _, attr := range user.Attributes {
			if attr.Name != nil && *attr.Name == "sub" {
				if attr.Value != nil {
					userSub = *attr.Value
					break
				}
			}
		}
	}

	// If sub attribute not found in ListUsers response, fetch it using AdminGetUser
	// This can happen if attributes are not included in ListUsers response
	if userSub == "" {
		adminInput := &cognitoidentityprovider.AdminGetUserInput{
			UserPoolId: aws.String(c.userPoolID),
			Username:   aws.String(username),
		}
		logger.DebugJSON("AdminGetUser Input (fallback)", adminInput)

		adminUser, err := c.client.AdminGetUser(ctx, adminInput)
		if err != nil {
			logger.DebugJSON("AdminGetUser Error (fallback)", err)
			return false, "", "", fmt.Errorf("failed to get UserSub for user: %w", err)
		}

		logger.DebugJSON("AdminGetUser Output (fallback)", adminUser)
		if adminUser.UserAttributes != nil {
			for _, attr := range adminUser.UserAttributes {
				if attr.Name != nil && *attr.Name == "sub" {
					if attr.Value != nil {
						userSub = *attr.Value
						break
					}
				}
			}
		}
		if userSub == "" {
			return false, "", "", errors.New("user found but UserSub is empty")
		}
	}

	// Check if user is confirmed
	// UserStatus can be: UNCONFIRMED, CONFIRMED, ARCHIVED, COMPROMISED, UNKNOWN, RESET_REQUIRED, FORCE_CHANGE_PASSWORD
	isConfirmed := user.UserStatus == types.UserStatusTypeConfirmed

	logger.Debug("User status check - Email: %s, Username: %s, UserSub: %s, Status: %s, Confirmed: %v",
		email, username, userSub, user.UserStatus, isConfirmed)

	// Return UserSub as cognitoId (third return value) - this is what we store in the database
	return isConfirmed, username, userSub, nil
}

// ResendConfirmationCode resends the confirmation code to the user.
func (c *Client) ResendConfirmationCode(ctx context.Context, username string) error {
	// Validate input parameters
	if username == "" {
		return apperrors.NewArgumentError("username", "cannot be empty")
	}

	// Check if we're using cognito-local (which doesn't support ResendConfirmationCode)
	if c.isLocalEndpoint() {
		// cognito-local doesn't support ResendConfirmationCode operation
		// In local development, we'll just log that the code would be resent
		logger.Debug("Local environment detected - ResendConfirmationCode not supported by cognito-local")
		logger.Debug("In production, confirmation code would be resent to: %s", username)
		return nil
	}

	input := &cognitoidentityprovider.ResendConfirmationCodeInput{
		ClientId:   aws.String(c.clientID),
		Username:   aws.String(username),
		SecretHash: c.getSecretHash(username),
	}

	logger.Info("Resending confirmation code - Username: %s, ClientID: %s",
		username, c.clientID)
	logger.DebugJSON("ResendConfirmationCode Input", input)

	output, err := c.client.ResendConfirmationCode(ctx, input)
	if err != nil {
		logger.Error("Error resending confirmation code: %v", err)
		logger.DebugJSON("ResendConfirmationCode Error", err)
		return fmt.Errorf("failed to resend confirmation code: %w", err)
	}

	logger.DebugJSON("ResendConfirmationCode Output", output)
	logger.Info("Confirmation code resent successfully - Username: %s", username)
	return nil
}

// GetUsernameByUserSub retrieves the username for a given UserSub (internal Cognito ID).
// This is needed because ConfirmSignUp requires username, not UserSub.
// For cognito-local, if email is provided, it uses email directly as username (since username = email in cognito-local).
// For AWS Cognito, if email is provided, it uses ListUsers to find the user by email and get the username.
func (c *Client) GetUsernameByUserSub(ctx context.Context, userSub string, email ...string) (string, error) {
	// Validate input parameters
	if userSub == "" {
		return "", apperrors.NewArgumentError("userSub", "cannot be empty")
	}

	// For cognito-local, username is the email, so we can use it directly if provided
	if c.isLocalEndpoint() && len(email) > 0 && email[0] != "" {
		username := email[0]
		logger.Debug("Using email as username for cognito-local - UserSub: %s, Email: %s", userSub, username)
		return username, nil
	}

	// For AWS Cognito, AdminGetUser doesn't accept UserSub directly as Username
	// If we have email, use ListUsers to find the user by email and get the username
	if len(email) > 0 && email[0] != "" && !c.isLocalEndpoint() {
		logger.Debug("Fetching username for UserSub: %s using email: %s", userSub, email[0])

		listInput := &cognitoidentityprovider.ListUsersInput{
			UserPoolId: aws.String(c.userPoolID),
			Filter:     aws.String(fmt.Sprintf("email = \"%s\"", email[0])),
			Limit:      aws.Int32(1),
		}

		logger.DebugJSON("ListUsers Input", listInput)

		listOutput, err := c.client.ListUsers(ctx, listInput)
		if err != nil {
			logger.Error("Error listing users by email: %v", err)
			logger.DebugJSON("ListUsers Error", err)
			// Fall through to try AdminGetUser
		} else {
			logger.DebugJSON("ListUsers Output", listOutput)

			if len(listOutput.Users) > 0 {
				user := listOutput.Users[0]
				if user.Username != nil {
					username := *user.Username
					logger.Debug("Found username via ListUsers - UserSub: %s, Username: %s", userSub, username)
					return username, nil
				}
			}
		}
	}

	// Fallback: Try AdminGetUser with UserSub (works in cognito-local, but not AWS Cognito)
	input := &cognitoidentityprovider.AdminGetUserInput{
		UserPoolId: aws.String(c.userPoolID),
		Username:   aws.String(userSub),
	}

	logger.Debug("Fetching username for UserSub: %s using AdminGetUser", userSub)
	logger.DebugJSON("AdminGetUser Input", input)

	output, err := c.client.AdminGetUser(ctx, input)
	if err != nil {
		logger.Error("Error fetching user by UserSub: %v", err)
		logger.DebugJSON("AdminGetUser Error", err)
		return "", fmt.Errorf("failed to fetch user by UserSub: %w", err)
	}

	logger.DebugJSON("AdminGetUser Output", output)

	if output.Username == nil {
		return "", errors.New("user found but username is empty")
	}

	username := *output.Username

	// If AdminGetUser returned the UserSub itself (happens in cognito-local),
	// we need to get the actual username from attributes
	if username == userSub && output.UserAttributes != nil {
		// Try to find username in attributes (for cognito-local)
		for _, attr := range output.UserAttributes {
			if attr.Name != nil && *attr.Name == "email" && attr.Value != nil {
				// In cognito-local, username = email
				if c.isLocalEndpoint() {
					username = *attr.Value
					logger.Debug("Found username from email attribute for cognito-local - UserSub: %s, Username: %s", userSub, username)
					return username, nil
				}
			}
		}
	}

	logger.Debug("Found username for UserSub %s: %s", userSub, username)
	return username, nil
}

// ConfirmSignUp confirms a user's signup with the provided confirmation code.
// It accepts cognitoId (which is the UserSub stored in the database) and confirmation code.
// Username is optional - if provided, it will be used directly (avoids ListUsers call).
// Email is optional but recommended for AWS Cognito if username is not provided.
// Returns an error if the code is invalid, expired, or if the user is already confirmed.
func (c *Client) ConfirmSignUp(ctx context.Context, cognitoID string, confirmationCode string, usernameOrEmail ...string) error {
	// Validate input parameters
	if cognitoID == "" {
		return apperrors.NewArgumentError("cognitoId", "cannot be empty")
	}
	if confirmationCode == "" {
		return apperrors.NewArgumentError("confirmationCode", "cannot be empty")
	}

	var username string
	var err error

	// If username is provided directly, use it (optimization to avoid ListUsers)
	if len(usernameOrEmail) > 0 && usernameOrEmail[0] != "" {
		// Check if it's a username (UUID format) or email
		// For cognito-local, username = email, so we can use it directly
		if c.isLocalEndpoint() {
			username = usernameOrEmail[0]
		} else {
			// For AWS Cognito, check if it looks like a UUID (username) or email
			// UUIDs are 36 chars with dashes, emails contain @
			if strings.Contains(usernameOrEmail[0], "@") {
				// It's an email, need to fetch username
				username, err = c.GetUsernameByUserSub(ctx, cognitoID, usernameOrEmail[0])
				if err != nil {
					return fmt.Errorf("failed to get username for UserSub: %w", err)
				}
			} else {
				// It's likely a username (UUID), use it directly
				username = usernameOrEmail[0]
			}
		}
	} else {
		// No username/email provided, need to fetch it
		username, err = c.GetUsernameByUserSub(ctx, cognitoID)
		if err != nil {
			return fmt.Errorf("failed to get username for UserSub: %w", err)
		}
	}

	input := &cognitoidentityprovider.ConfirmSignUpInput{
		ClientId:         aws.String(c.clientID),
		Username:         aws.String(username),
		ConfirmationCode: aws.String(confirmationCode),
		SecretHash:       c.getSecretHash(username),
	}

	logger.Info("Validating confirmation code - UserSub: %s, Username: %s, ClientID: %s",
		cognitoID, username, c.clientID)

	_, err = c.client.ConfirmSignUp(ctx, input)
	if err != nil {
		logger.Error("Error validating confirmation code: %v", err)
		return fmt.Errorf("failed to validate confirmation code: %w", err)
	}

	logger.Info("Confirmation code validated successfully - UserSub: %s", cognitoID)
	return nil
}

// InitiateAuth initiates authentication for a user and returns tokens.
// It uses USER_PASSWORD_AUTH flow.
func (c *Client) InitiateAuth(ctx context.Context, cognitoID, password string) (*types.AuthenticationResultType, error) {
	// Validate input parameters
	if cognitoID == "" {
		return nil, apperrors.NewArgumentError("cognitoId", "cannot be empty")
	}
	if password == "" {
		return nil, apperrors.NewArgumentError("password", "cannot be empty")
	}

	authParams := map[string]string{
		"USERNAME": cognitoID,
		"PASSWORD": password,
	}

	if secretHash := c.getSecretHash(cognitoID); secretHash != nil {
		authParams["SECRET_HASH"] = *secretHash
	}

	input := &cognitoidentityprovider.InitiateAuthInput{
		AuthFlow:       types.AuthFlowTypeUserPasswordAuth,
		ClientId:       aws.String(c.clientID),
		AuthParameters: authParams,
	}

	logger.Info("Initiating auth - CognitoID: %s, ClientID: %s", cognitoID, c.clientID)
	logger.DebugJSON("InitiateAuth Input", input)

	output, err := c.client.InitiateAuth(ctx, input)
	if err != nil {
		logger.Error("Error initiating auth: %v", err)
		logger.DebugJSON("InitiateAuth Error", err)
		return nil, fmt.Errorf("failed to initiate auth: %w", err)
	}

	logger.DebugJSON("InitiateAuth Output", output)

	if output.AuthenticationResult == nil {
		logger.Error("InitiateAuth returned nil AuthenticationResult")
		return nil, errors.New("cognito initiate auth did not return result")
	}

	logger.Info("Auth successful - CognitoID: %s", cognitoID)
	return output.AuthenticationResult, nil
}
