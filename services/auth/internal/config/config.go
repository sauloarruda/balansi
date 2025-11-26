package config

import (
	"fmt"
	"os"
	"strings"
)

type Config struct {
	DatabaseURL      string
	EncryptionSecret string
	FrontendDomain   string // Optional: frontend domain for CORS validation
	Stage            string // Optional: API Gateway stage (e.g., "prod", "dev", "bal-7")
	// Cognito
	CognitoUserPoolID   string
	CognitoClientID     string
	CognitoClientSecret string // Optional: required if client has secret
	CognitoEndpoint     string
	AWSRegion           string // Optional: AWS region for Cognito (defaults to extracting from User Pool ID)
}

// requireEnvVar gets a required environment variable and panics if it's missing
func requireEnvVar(name string) string {
	value := os.Getenv(name)
	if value == "" {
		panic(fmt.Sprintf("Missing required environment variable: %s", name))
	}
	return value
}

// optionalEnvVar gets an optional environment variable (empty string if not set)
func optionalEnvVar(name string) string {
	return os.Getenv(name)
}

func Load() (*Config, error) {
	databaseURL := requireEnvVar("DATABASE_URL")
	encryptionSecret := requireEnvVar("ENCRYPTION_SECRET")

	// Frontend domain - optional, used for CORS validation
	frontendDomain := optionalEnvVar("FRONTEND_DOMAIN")

	// Stage - optional, API Gateway stage (used for path stripping)
	stage := optionalEnvVar("STAGE")

	cognitoUserPoolID := requireEnvVar("COGNITO_USER_POOL_ID")
	cognitoClientID := requireEnvVar("COGNITO_CLIENT_ID")

	// Cognito client secret - optional, only needed if client has secret configured
	cognitoClientSecret := optionalEnvVar("COGNITO_CLIENT_SECRET")

	// Cognito endpoint - empty means use AWS default endpoint (for production/Lambda)
	// Set to http://localhost:9229 for local development with cognito-local
	cognitoEndpoint := optionalEnvVar("COGNITO_ENDPOINT")

	// AWS region - determine from env var, User Pool ID, or default
	awsRegion := optionalEnvVar("AWS_REGION")
	if awsRegion == "" {
		// Extract region from User Pool ID format: us-east-2_XXXXXXXXX
		parts := strings.Split(cognitoUserPoolID, "_")
		if len(parts) > 0 {
			awsRegion = parts[0]
		}
		// Fallback to default if still empty
		if awsRegion == "" {
			awsRegion = "us-east-2"
		}
	}

	return &Config{
		DatabaseURL:         databaseURL,
		EncryptionSecret:    encryptionSecret,
		FrontendDomain:      frontendDomain,
		Stage:               stage,
		CognitoUserPoolID:   cognitoUserPoolID,
		CognitoClientID:     cognitoClientID,
		CognitoClientSecret: cognitoClientSecret,
		CognitoEndpoint:     cognitoEndpoint,
		AWSRegion:           awsRegion,
	}, nil
}
