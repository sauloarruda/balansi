package handlers

import (
	"context"
	"encoding/json"
	"services/auth/internal/cognito"
	"services/auth/internal/http"
	"services/auth/internal/jwt"
	"services/auth/internal/logger"
	"services/auth/internal/models"
	"services/auth/internal/repositories"
	"services/auth/internal/testhelpers"

	"github.com/aws/aws-lambda-go/events"
)

type MeHandler struct {
	userRepo      testhelpers.UserRepositoryInterface
	cognitoClient testhelpers.CognitoClientInterface
	jwtValidator  *jwt.Validator
}

func NewMeHandler(userRepo *repositories.UserRepository, cognitoClient *cognito.Client, jwtValidator *jwt.Validator) *MeHandler {
	return NewMeHandlerWithInterface(userRepo, cognitoClient, jwtValidator)
}

func NewMeHandlerWithInterface(userRepo testhelpers.UserRepositoryInterface, cognitoClient testhelpers.CognitoClientInterface, jwtValidator *jwt.Validator) *MeHandler {
	return &MeHandler{
		userRepo:      userRepo,
		cognitoClient: cognitoClient,
		jwtValidator:  jwtValidator,
	}
}

func (h *MeHandler) Handle(ctx context.Context, req events.APIGatewayV2HTTPRequest) (events.APIGatewayV2HTTPResponse, error) {
	// Extract Authorization header
	authHeader := req.Headers["authorization"]
	if authHeader == "" {
		authHeader = req.Headers["Authorization"]
	}

	if authHeader == "" {
		return errorResponse(401, "unauthorized", "Missing authorization header"), nil
	}

	// Extract access token from "Bearer <token>"
	accessToken := http.ExtractBearerToken(authHeader)
	if accessToken == "" {
		return errorResponse(401, "unauthorized", "Invalid authorization header"), nil
	}

	// Validate token signature using JWKS and get user sub (Cognito ID)
	userSub, err := h.jwtValidator.ValidateToken(ctx, accessToken)
	if err != nil {
		logger.Error("Failed to validate access token: %v", err)
		return errorResponse(401, "invalid_token", "Invalid access token"), nil
	}

	// Find user by CognitoID
	user, err := h.userRepo.FindByCognitoID(ctx, userSub)
	if err != nil {
		logger.Error("Failed to find user: %v", err)
		return errorResponse(500, "internal_error", "Internal server error"), nil
	}

	if user == nil {
		return errorResponse(404, "user_not_found", "User not found"), nil
	}

	// Return user info
	userInfo := &models.UserInfoResponse{
		ID:   user.ID,
		Name: user.Name,
	}

	body, err := json.Marshal(userInfo)
	if err != nil {
		logger.Error("Failed to marshal response: %v", err)
		return errorResponse(500, "internal_error", "Failed to marshal response"), nil
	}

	return events.APIGatewayV2HTTPResponse{
		StatusCode: 200,
		Headers: map[string]string{
			"Content-Type": "application/json",
		},
		Body: string(body),
	}, nil
}
