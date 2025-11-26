package services

import (
	"services/auth/internal/testhelpers"
)

// UserRepositoryInterface defines repository operations (aliased for convenience).
type UserRepositoryInterface = testhelpers.UserRepositoryInterface

// CognitoClientInterface defines Cognito client operations (aliased for convenience).
type CognitoClientInterface = testhelpers.CognitoClientInterface
