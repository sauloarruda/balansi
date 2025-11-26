package main

import (
	"context"
	"os"
	"os/signal"
	"services/auth/internal/cognito"
	"services/auth/internal/config"
	"services/auth/internal/handlers"
	httputils "services/auth/internal/http"
	"services/auth/internal/jwt"
	"services/auth/internal/logger"
	"services/auth/internal/repositories"
	"services/auth/internal/services"
	"syscall"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
	"github.com/jackc/pgx/v5/pgxpool"
)

var (
	signupHandler         *handlers.SignupHandler
	confirmHandler        *handlers.ConfirmHandler
	refreshHandler        *handlers.RefreshHandler
	meHandler             *handlers.MeHandler
	forgotPasswordHandler *handlers.ForgotPasswordHandler
	resetPasswordHandler  *handlers.ResetPasswordHandler
	logoutHandler         *handlers.LogoutHandler
	dbPool                *pgxpool.Pool
	cfg                   *config.Config
	handlerRegistry       *httputils.HandlerRegistry
)

// loadConfiguration loads and returns the application configuration
func loadConfiguration() *config.Config {
	cfg, err := config.Load()
	if err != nil {
		logger.Error("Failed to load config: %v", err)
		os.Exit(1)
	}
	return cfg
}

// connectDatabase establishes a connection to the database and returns the pool
func connectDatabase(cfg *config.Config) *pgxpool.Pool {
	db, err := pgxpool.New(context.Background(), cfg.DatabaseURL)
	if err != nil {
		logger.Error("Failed to connect to database: %v", err)
		os.Exit(1)
	}
	return db
}

// initializeRepositories creates and returns the application repositories
func initializeRepositories(db *pgxpool.Pool) *repositories.UserRepository {
	return repositories.NewUserRepository(db)
}

// initializeCognitoClient creates and returns the Cognito client
func initializeCognitoClient(cfg *config.Config) *cognito.Client {
	cognitoClient, err := cognito.NewClient(cfg)
	if err != nil {
		logger.Error("Failed to create Cognito client: %v", err)
		os.Exit(1)
	}
	return cognitoClient
}

// initializeJWTValidator creates and returns the JWT validator
func initializeJWTValidator(cfg *config.Config) *jwt.Validator {
	return jwt.NewValidator(cfg)
}

// initializeServices creates and returns the application services
func initializeServices(userRepo *repositories.UserRepository, cognitoClient *cognito.Client, cfg *config.Config) (*services.SignupService, *services.SessionService, *services.PasswordRecoveryService) {
	signupService := services.NewSignupService(userRepo, cognitoClient, cfg.EncryptionSecret)
	sessionService := services.NewSessionService(userRepo, cognitoClient, cfg.EncryptionSecret)
	passwordRecoveryService := services.NewPasswordRecoveryService(userRepo, cognitoClient)
	return signupService, sessionService, passwordRecoveryService
}

// initializeHandlers creates and initializes all the HTTP handlers
func initializeHandlers(signupService *services.SignupService, sessionService *services.SessionService, passwordRecoveryService *services.PasswordRecoveryService, userRepo *repositories.UserRepository, cognitoClient *cognito.Client, jwtValidator *jwt.Validator) {
	signupHandler = handlers.NewSignupHandler(signupService)
	confirmHandler = handlers.NewConfirmHandler(signupService, sessionService)
	refreshHandler = handlers.NewRefreshHandler(sessionService)
	meHandler = handlers.NewMeHandler(userRepo, cognitoClient, jwtValidator)
	forgotPasswordHandler = handlers.NewForgotPasswordHandler(passwordRecoveryService)
	resetPasswordHandler = handlers.NewResetPasswordHandler(passwordRecoveryService)
	logoutHandler = handlers.NewLogoutHandler()
}

func init() {
	// Load configuration
	cfg = loadConfiguration()

	// Connect to database
	db := connectDatabase(cfg)
	dbPool = db

	// Initialize repositories
	userRepo := initializeRepositories(db)

	// Initialize Cognito client
	cognitoClient := initializeCognitoClient(cfg)

	// Initialize JWT validator
	jwtValidator := initializeJWTValidator(cfg)

	// Initialize services
	signupService, sessionService, passwordRecoveryService := initializeServices(userRepo, cognitoClient, cfg)

	// Initialize handlers
	initializeHandlers(signupService, sessionService, passwordRecoveryService, userRepo, cognitoClient, jwtValidator)

	// Create handler registry for unified processing
	handlerRegistry = &httputils.HandlerRegistry{
		Routes: []httputils.RouteConfig{
			{Path: "/auth/sign-up", Method: "POST"},
			{Path: "/auth/confirm", Method: "POST"},
			{Path: "/auth/refresh", Method: "POST"},
			{Path: "/auth/me", Method: "GET"},
			{Path: "/auth/forgot-password", Method: "POST"},
			{Path: "/auth/reset-password", Method: "POST"},
			{Path: "/auth/logout", Method: "POST"},
		},
		SignupHandler: func(ctx context.Context, req events.APIGatewayV2HTTPRequest) (events.APIGatewayV2HTTPResponse, error) {
			return signupHandler.Handle(ctx, req)
		},
		ConfirmHandler: func(ctx context.Context, req events.APIGatewayV2HTTPRequest) (events.APIGatewayV2HTTPResponse, error) {
			return confirmHandler.Handle(ctx, req)
		},
		RefreshHandler: func(ctx context.Context, req events.APIGatewayV2HTTPRequest) (events.APIGatewayV2HTTPResponse, error) {
			return refreshHandler.Handle(ctx, req)
		},
		MeHandler: func(ctx context.Context, req events.APIGatewayV2HTTPRequest) (events.APIGatewayV2HTTPResponse, error) {
			return meHandler.Handle(ctx, req)
		},
		ForgotPasswordHandler: func(ctx context.Context, req events.APIGatewayV2HTTPRequest) (events.APIGatewayV2HTTPResponse, error) {
			return forgotPasswordHandler.Handle(ctx, req)
		},
		ResetPasswordHandler: func(ctx context.Context, req events.APIGatewayV2HTTPRequest) (events.APIGatewayV2HTTPResponse, error) {
			return resetPasswordHandler.Handle(ctx, req)
		},
		LogoutHandler: func(ctx context.Context, req events.APIGatewayV2HTTPRequest) (events.APIGatewayV2HTTPResponse, error) {
			return logoutHandler.Handle(ctx, req)
		},
	}

}

func cleanup() {
	if dbPool != nil {
		logger.Info("Closing database connection pool...")
		dbPool.Close()
	}
}

// Lambda handler wrapper that ensures cleanup on context cancellation.
func lambdaHandler(ctx context.Context, req events.APIGatewayV2HTTPRequest) (events.APIGatewayV2HTTPResponse, error) {
	// In Lambda, the pool is kept alive for container reuse
	// But we handle context cancellation properly
	select {
	case <-ctx.Done():
		return events.APIGatewayV2HTTPResponse{
			StatusCode: 503,
			Body:       `{"error": "Request cancelled"}`,
		}, ctx.Err()
	default:
		return httputils.HandleLambdaRequest(ctx, req, cfg.FrontendDomain, handlerRegistry)
	}
}

func main() {
	if os.Getenv("AWS_LAMBDA_RUNTIME_API") != "" {
		// Running as Lambda
		// Note: In Lambda, the connection pool is kept alive for container reuse
		// The pool will be closed when the container is terminated by AWS
		lambda.Start(lambdaHandler)
	} else {
		// Running locally (for testing)
		// Setup signal handling for graceful shutdown
		sigChan := make(chan os.Signal, 1)
		signal.Notify(sigChan, os.Interrupt, syscall.SIGTERM)

		go func() {
			<-sigChan
			logger.Info("Shutting down...")
			cleanup()
			os.Exit(0)
		}()

		// Ensure cleanup on exit
		defer cleanup()

		httputils.StartLocalServer(handlerRegistry)
	}
}
