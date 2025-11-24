package cognito

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"errors"
	"fmt"
	"log"
	"services/auth/internal/config"
	apperrors "services/auth/internal/errors"
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
	ResendConfirmationCode(ctx context.Context, params *cognitoidentityprovider.ResendConfirmationCodeInput, optFns ...func(*cognitoidentityprovider.Options)) (*cognitoidentityprovider.ResendConfirmationCodeOutput, error)
	ConfirmSignUp(ctx context.Context, params *cognitoidentityprovider.ConfirmSignUpInput, optFns ...func(*cognitoidentityprovider.Options)) (*cognitoidentityprovider.ConfirmSignUpOutput, error)
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
		log.Printf("Configuring Cognito client with custom endpoint: %s", cfg.CognitoEndpoint)
		clientOpts = append(clientOpts, func(o *cognitoidentityprovider.Options) {
			o.BaseEndpoint = aws.String(cfg.CognitoEndpoint)
		})
	}

	client := cognitoidentityprovider.NewFromConfig(awsCfg, clientOpts...)

	log.Printf("Cognito client initialized - UserPoolID: %s, ClientID: %s, Endpoint: %s",
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
		log.Printf("Using email as username for cognito-local")
	} else {
		// AWS Cognito with email alias requires UUID as username
		username = uuid.New().String()
		log.Printf("Using UUID as username for AWS Cognito")
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

	log.Printf("Calling Cognito SignUp - Email: %s, ClientID: %s, UserPoolID: %s",
		email, c.clientID, c.userPoolID)

	output, err := c.client.SignUp(ctx, input)
	if err != nil {
		log.Printf("Cognito SignUp error: %v", err)
		return "", fmt.Errorf("cognito signup failed: %w", err)
	}

	if output.UserSub == nil {
		log.Printf("Cognito SignUp returned nil UserSub")
		return "", errors.New("cognito signup did not return user sub")
	}

	log.Printf("Cognito SignUp successful - Username: %s, UserSub: %s", username, *output.UserSub)
	// Return username instead of UserSub, as ConfirmSignUp uses username as the key
	return username, nil
}

// IsUserConfirmed checks if a user is confirmed in Cognito
// It tries to find the user by email and checks their status
// Returns: isConfirmed, username, cognitoId (username to be stored), error.
// The cognitoId returned is the username, which is what we store in the database and use for ConfirmSignUp.
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

	output, err := c.client.ListUsers(ctx, input)
	if err != nil {
		log.Printf("Error listing users: %v", err)
		return false, "", "", fmt.Errorf("failed to list users: %w", err)
	}

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

	// Check if user is confirmed
	// UserStatus can be: UNCONFIRMED, CONFIRMED, ARCHIVED, COMPROMISED, UNKNOWN, RESET_REQUIRED, FORCE_CHANGE_PASSWORD
	isConfirmed := user.UserStatus == types.UserStatusTypeConfirmed

	log.Printf("User status check - Email: %s, Username: %s, Status: %s, Confirmed: %v",
		email, username, user.UserStatus, isConfirmed)

	// Return username as cognitoId (third return value) - this is what we store in the database
	return isConfirmed, username, username, nil
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
		log.Printf("Local environment detected - ResendConfirmationCode not supported by cognito-local")
		log.Printf("In production, confirmation code would be resent to: %s", username)
		return nil
	}

	input := &cognitoidentityprovider.ResendConfirmationCodeInput{
		ClientId:   aws.String(c.clientID),
		Username:   aws.String(username),
		SecretHash: c.getSecretHash(username),
	}

	log.Printf("Resending confirmation code - Username: %s, ClientID: %s",
		username, c.clientID)

	_, err := c.client.ResendConfirmationCode(ctx, input)
	if err != nil {
		log.Printf("Error resending confirmation code: %v", err)
		return fmt.Errorf("failed to resend confirmation code: %w", err)
	}

	log.Printf("Confirmation code resent successfully - Username: %s", username)
	return nil
}

// ConfirmSignUp confirms a user's signup with the provided confirmation code.
// It accepts cognitoId (which is the username stored in the database) and confirmation code.
// Returns an error if the code is invalid, expired, or if the user is already confirmed.
func (c *Client) ConfirmSignUp(ctx context.Context, cognitoID string, confirmationCode string) error {
	// Validate input parameters
	if cognitoID == "" {
		return apperrors.NewArgumentError("cognitoId", "cannot be empty")
	}
	if confirmationCode == "" {
		return apperrors.NewArgumentError("confirmationCode", "cannot be empty")
	}

	// cognitoID is the username that was returned from SignUp and stored in the database
	input := &cognitoidentityprovider.ConfirmSignUpInput{
		ClientId:         aws.String(c.clientID),
		Username:         aws.String(cognitoID),
		ConfirmationCode: aws.String(confirmationCode),
		SecretHash:       c.getSecretHash(cognitoID),
	}

	log.Printf("Validating confirmation code - CognitoID: %s, ClientID: %s",
		cognitoID, c.clientID)

	_, err := c.client.ConfirmSignUp(ctx, input)
	if err != nil {
		log.Printf("Error validating confirmation code: %v", err)
		return fmt.Errorf("failed to validate confirmation code: %w", err)
	}

	log.Printf("Confirmation code validated successfully - CognitoID: %s", cognitoID)
	return nil
}
