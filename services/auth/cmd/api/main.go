package main

import (
	"context"
	"io"
	"log"
	"net/http"
	"os"
	"os/signal"
	"services/auth/internal/cognito"
	"services/auth/internal/config"
	"services/auth/internal/handlers"
	"services/auth/internal/repositories"
	"services/auth/internal/services"
	"strings"
	"syscall"
	"time"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
	"github.com/jackc/pgx/v5/pgxpool"
)

var (
	signupHandler  *handlers.SignupHandler
	confirmHandler *handlers.ConfirmHandler
	dbPool         *pgxpool.Pool
)

func init() {
	// Load configuration
	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("Failed to load config: %v", err)
	}

	// Connect to database
	db, err := pgxpool.New(context.Background(), cfg.DatabaseURL)
	if err != nil {
		log.Fatalf("Failed to connect to database: %v", err)
	}
	dbPool = db

	// Initialize repositories
	userRepo := repositories.NewUserRepository(db)

	// Initialize Cognito client
	cognitoClient, err := cognito.NewClient(cfg)
	if err != nil {
		log.Fatalf("Failed to create Cognito client: %v", err)
	}

	// Initialize services
	signupService := services.NewSignupService(userRepo, cognitoClient, cfg.EncryptionSecret)

	// Initialize handlers
	signupHandler = handlers.NewSignupHandler(signupService)
	confirmHandler = handlers.NewConfirmHandler(signupService)
}

func cleanup() {
	if dbPool != nil {
		log.Println("Closing database connection pool...")
		dbPool.Close()
	}
}

func methodNotAllowedResponse() events.APIGatewayV2HTTPResponse {
	return events.APIGatewayV2HTTPResponse{
		StatusCode: 405,
		Headers: map[string]string{
			"Content-Type": "application/json",
		},
		Body: `{"error": "Method not allowed"}`,
	}
}

func handler(ctx context.Context, req events.APIGatewayV2HTTPRequest) (events.APIGatewayV2HTTPResponse, error) {
	log.Printf("Received request: RawPath='%s', Path='%s', Method='%s'",
		req.RawPath, req.RequestContext.HTTP.Path, req.RequestContext.HTTP.Method)

	// Simple routing based on path
	path := req.RequestContext.HTTP.Path
	if path == "" {
		path = req.RawPath
	}

	// Strip stage from path if present
	stage := os.Getenv("STAGE")
	if stage != "" {
		prefix := "/" + stage
		if strings.HasPrefix(path, prefix) {
			path = strings.TrimPrefix(path, prefix)
		}
	}

	switch path {
	case "/auth/sign-up":
		if req.RequestContext.HTTP.Method == "POST" {
			return signupHandler.Handle(ctx, req)
		}
		return methodNotAllowedResponse(), nil
	case "/auth/confirm":
		if req.RequestContext.HTTP.Method == "POST" {
			return confirmHandler.Handle(ctx, req)
		}
		return methodNotAllowedResponse(), nil
	default:
		return events.APIGatewayV2HTTPResponse{
			StatusCode: 404,
			Headers: map[string]string{
				"Content-Type": "application/json",
			},
			Body: `{"error": "Not found", "path": "` + path + `"}`,
		}, nil
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
		return handler(ctx, req)
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
			log.Println("Shutting down...")
			cleanup()
			os.Exit(0)
		}()

		// Ensure cleanup on exit
		defer cleanup()

		startLocalServer()
	}
}

func startLocalServer() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "3000"
	}

	handlerFunc := func(w http.ResponseWriter, r *http.Request) {
		// Get origin from request
		origin := r.Header.Get("Origin")
		if origin == "" {
			// Fallback for same-origin requests
			origin = "*"
		}

		// Handle CORS preflight
		if r.Method == "OPTIONS" {
			w.Header().Set("Access-Control-Allow-Origin", origin)
			w.Header().Set("Access-Control-Allow-Methods", "POST, OPTIONS")
			w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization")
			w.Header().Set("Access-Control-Allow-Credentials", "true")
			w.WriteHeader(200)
			return
		}

		// Read request body
		body := ""
		if r.Body != nil {
			bodyBytes, err := io.ReadAll(r.Body)
			if err == nil {
				body = string(bodyBytes)
			}
		}

		// Create APIGatewayV2HTTPRequest
		req := events.APIGatewayV2HTTPRequest{
			RawPath:        r.URL.Path,
			RawQueryString: r.URL.RawQuery,
			Headers:        make(map[string]string),
			Body:           body,
			RequestContext: events.APIGatewayV2HTTPRequestContext{
				HTTP: events.APIGatewayV2HTTPRequestContextHTTPDescription{
					Method: r.Method,
					Path:   r.URL.Path,
				},
			},
		}

		// Copy headers
		for k, v := range r.Header {
			if len(v) > 0 {
				req.Headers[k] = v[0]
			}
		}

		// Call handler
		ctx := context.Background()
		resp, err := handler(ctx, req)
		if err != nil {
			log.Printf("Handler error: %v", err)
			w.WriteHeader(500)
			if _, writeErr := w.Write([]byte(`{"error": "Internal server error"}`)); writeErr != nil {
				log.Printf("Failed to write error response: %v", writeErr)
			}
			return
		}

		// Add CORS headers to response
		// When using credentials: 'include', we must use specific origin, not '*'
		w.Header().Set("Access-Control-Allow-Origin", origin)
		w.Header().Set("Access-Control-Allow-Methods", "POST, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization")
		w.Header().Set("Access-Control-Allow-Credentials", "true")

		// Write response
		for k, v := range resp.Headers {
			w.Header().Set(k, v)
		}
		w.WriteHeader(resp.StatusCode)
		if _, writeErr := w.Write([]byte(resp.Body)); writeErr != nil {
			log.Printf("Failed to write response: %v", writeErr)
		}
	}

	http.HandleFunc("/auth/sign-up", handlerFunc)
	http.HandleFunc("/auth/confirm", handlerFunc)

	log.Printf("Server starting on port %s", port)
	log.Printf("Test endpoint: POST http://localhost:%s/auth/sign-up", port)
	log.Printf("Test endpoint: POST http://localhost:%s/auth/confirm", port)
	server := &http.Server{
		Addr:              ":" + port,
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       10 * time.Second,
		WriteTimeout:      10 * time.Second,
		IdleTimeout:       60 * time.Second,
	}
	if err := server.ListenAndServe(); err != nil {
		log.Fatalf("Failed to start server: %v", err)
	}
}
