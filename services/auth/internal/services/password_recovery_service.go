package services

import (
	"context"
	"errors"
	"fmt"
	"services/auth/internal/cognito"
	"services/auth/internal/logger"
	"services/auth/internal/repositories"
	"strings"

	"github.com/aws/aws-sdk-go-v2/service/cognitoidentityprovider/types"
)

var (
	ErrUserNotFoundForRecovery = errors.New("user not found for password recovery")
	ErrInvalidRecoveryCode     = errors.New("invalid recovery code")
	ErrExpiredRecoveryCode     = errors.New("expired recovery code")
	ErrPasswordPolicyViolation = errors.New("password does not meet requirements")
	ErrTooManyAttempts         = errors.New("too many failed attempts")
)

// PasswordRecoveryService handles password recovery operations.
type PasswordRecoveryService struct {
	userRepo      UserRepositoryInterface
	cognitoClient CognitoClientInterface
}

// NewPasswordRecoveryService creates a new PasswordRecoveryService with concrete implementations.
func NewPasswordRecoveryService(
	userRepo *repositories.UserRepository,
	cognitoClient *cognito.Client,
) *PasswordRecoveryService {
	return NewPasswordRecoveryServiceWithInterfaces(userRepo, cognitoClient)
}

// NewPasswordRecoveryServiceWithInterfaces creates a new PasswordRecoveryService with interface-based dependencies.
// This allows for easier testing with mocks.
func NewPasswordRecoveryServiceWithInterfaces(
	userRepo UserRepositoryInterface,
	cognitoClient CognitoClientInterface,
) *PasswordRecoveryService {
	return &PasswordRecoveryService{
		userRepo:      userRepo,
		cognitoClient: cognitoClient,
	}
}

// ForgotPassword initiates password recovery by sending a confirmation code to the user's email.
func (s *PasswordRecoveryService) ForgotPassword(ctx context.Context, email string) error {
	// Validate email
	if email == "" {
		return fmt.Errorf("email cannot be empty")
	}

	// Check if user exists in our database
	user, err := s.userRepo.FindByEmail(ctx, email)
	if err != nil {
		return fmt.Errorf("failed to check user existence: %w", err)
	}

	// User enumeration protection: return success even if user doesn't exist
	if user == nil || user.CognitoID == nil {
		// We return ErrUserNotFoundForRecovery here to let the handler layer decide how to handle it
		// (e.g. return generic success to client but log the error)
		return ErrUserNotFoundForRecovery
	}

	// Call Cognito ForgotPassword API
	codeDeliveryDetails, err := s.cognitoClient.ForgotPassword(ctx, email)
	if err != nil {
		// Map Cognito errors to our error types
		return s.mapForgotPasswordError(err)
	}

	if codeDeliveryDetails == nil {
		return errors.New("cognito forgot password did not return delivery details")
	}

	deliveryMedium := ""
	if codeDeliveryDetails.DeliveryMedium != "" {
		deliveryMedium = string(codeDeliveryDetails.DeliveryMedium)
	}

	logger.Info("Password recovery code sent successfully - Email: %s, Medium: %s",
		email, deliveryMedium)

	return nil
}

// ResetPassword confirms password reset with the provided code and new password.
func (s *PasswordRecoveryService) ResetPassword(ctx context.Context, email, code, newPassword string) error {
	// Validate inputs
	if email == "" {
		return fmt.Errorf("email cannot be empty")
	}
	if code == "" {
		return fmt.Errorf("code cannot be empty")
	}
	if newPassword == "" {
		return fmt.Errorf("newPassword cannot be empty")
	}

	// Check if user exists in our database
	user, err := s.userRepo.FindByEmail(ctx, email)
	if err != nil {
		return fmt.Errorf("failed to check user existence: %w", err)
	}

	if user == nil {
		return ErrUserNotFoundForRecovery
	}

	// Check if user has Cognito ID
	if user.CognitoID == nil {
		return ErrUserNotFoundForRecovery
	}

	// Call Cognito ConfirmForgotPassword API
	err = s.cognitoClient.ResetPassword(ctx, email, code, newPassword)
	if err != nil {
		// Map Cognito errors to our error types
		return s.mapResetPasswordError(err)
	}

	logger.Info("Password reset successfully - Email: %s", email)
	return nil
}

// mapForgotPasswordError maps Cognito errors to our application errors.
func (s *PasswordRecoveryService) mapForgotPasswordError(err error) error {
	var userNotFoundErr *types.UserNotFoundException
	var limitExceededErr *types.LimitExceededException
	var tooManyAttemptsErr *types.TooManyFailedAttemptsException

	if errors.As(err, &userNotFoundErr) {
		return ErrUserNotFoundForRecovery
	}
	if errors.As(err, &limitExceededErr) || errors.As(err, &tooManyAttemptsErr) {
		return ErrTooManyAttempts
	}

	// Fallback: Check error string if types don't match (e.g. cognito-local issues)
	errStr := err.Error()
	if strings.Contains(errStr, "UserNotFoundException") || strings.Contains(errStr, "User does not exist") {
		return ErrUserNotFoundForRecovery
	}
	if strings.Contains(errStr, "LimitExceededException") || strings.Contains(errStr, "TooManyFailedAttemptsException") {
		return ErrTooManyAttempts
	}

	return fmt.Errorf("failed to initiate password recovery: %w", err)
}

// mapResetPasswordError maps Cognito errors to our application errors.
func (s *PasswordRecoveryService) mapResetPasswordError(err error) error {
	var codeMismatchErr *types.CodeMismatchException
	var expiredCodeErr *types.ExpiredCodeException
	var invalidPasswordErr *types.InvalidPasswordException
	var userNotFoundErr *types.UserNotFoundException
	var limitExceededErr *types.LimitExceededException
	var tooManyAttemptsErr *types.TooManyFailedAttemptsException

	if errors.As(err, &codeMismatchErr) {
		return ErrInvalidRecoveryCode
	}
	if errors.As(err, &expiredCodeErr) {
		return ErrExpiredRecoveryCode
	}
	if errors.As(err, &invalidPasswordErr) {
		return ErrPasswordPolicyViolation
	}
	if errors.As(err, &userNotFoundErr) {
		return ErrUserNotFoundForRecovery
	}
	if errors.As(err, &limitExceededErr) || errors.As(err, &tooManyAttemptsErr) {
		return ErrTooManyAttempts
	}

	// Fallback: Check error string if types don't match (e.g. cognito-local issues)
	errStr := err.Error()
	if strings.Contains(errStr, "CodeMismatchException") || strings.Contains(errStr, "Invalid verification code") {
		return ErrInvalidRecoveryCode
	}
	if strings.Contains(errStr, "ExpiredCodeException") || strings.Contains(errStr, "Invalid code provided") {
		return ErrExpiredRecoveryCode
	}
	if strings.Contains(errStr, "InvalidPasswordException") || strings.Contains(errStr, "Password did not conform") {
		return ErrPasswordPolicyViolation
	}
	if strings.Contains(errStr, "UserNotFoundException") || strings.Contains(errStr, "User does not exist") {
		return ErrUserNotFoundForRecovery
	}
	if strings.Contains(errStr, "LimitExceededException") || strings.Contains(errStr, "TooManyFailedAttemptsException") {
		return ErrTooManyAttempts
	}

	return fmt.Errorf("failed to reset password: %w", err)
}
