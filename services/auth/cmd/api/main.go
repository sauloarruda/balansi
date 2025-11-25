package main

import (
	"context"
	"io"
	"log"
	"net/http"
	"net/url"
	"os"
	"os/signal"
	"services/auth/internal/cognito"
	"services/auth/internal/config"
	"services/auth/internal/handlers"
	"services/auth/internal/jwt"
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
	refreshHandler *handlers.RefreshHandler
	meHandler      *handlers.MeHandler
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

	// Initialize JWT validator
	jwtValidator := jwt.NewValidator(cfg)

	// Initialize services
	signupService := services.NewSignupService(userRepo, cognitoClient, cfg.EncryptionSecret)
	sessionService := services.NewSessionService(userRepo, cognitoClient, cfg.EncryptionSecret)

	// Initialize handlers
	signupHandler = handlers.NewSignupHandler(signupService)
	confirmHandler = handlers.NewConfirmHandler(signupService, sessionService)
	refreshHandler = handlers.NewRefreshHandler(sessionService)
	meHandler = handlers.NewMeHandler(userRepo, cognitoClient, jwtValidator)
}

func cleanup() {
	if dbPool != nil {
		log.Println("Closing database connection pool...")
		dbPool.Close()
	}
}

// validateOrigin validates the origin against FRONTEND_DOMAIN if configured
// Returns the validated origin or empty string if validation fails
func validateOrigin(requestOrigin string) string {
	// If no origin in request, return empty (will be handled by caller)
	if requestOrigin == "" {
		return ""
	}

	// Get configured frontend domain from environment
	frontendDomain := os.Getenv("FRONTEND_DOMAIN")
	if frontendDomain == "" {
		// No FRONTEND_DOMAIN configured, accept any origin (fallback behavior)
		return requestOrigin
	}

	// Parse request origin URL
	originURL, err := url.Parse(requestOrigin)
	if err != nil {
		log.Printf("Invalid origin URL: %s", requestOrigin)
		return ""
	}

	originHost := originURL.Host
	// Remove port if present
	if idx := strings.Index(originHost, ":"); idx != -1 {
		originHost = originHost[:idx]
	}

	// Normalize frontend domain (remove port if present, remove protocol if present)
	normalizedFrontendDomain := frontendDomain
	if idx := strings.Index(normalizedFrontendDomain, "://"); idx != -1 {
		normalizedFrontendDomain = normalizedFrontendDomain[idx+3:]
	}
	if idx := strings.Index(normalizedFrontendDomain, ":"); idx != -1 {
		normalizedFrontendDomain = normalizedFrontendDomain[:idx]
	}

	// Check if origin matches frontend domain exactly
	if originHost == normalizedFrontendDomain {
		return requestOrigin
	}

	// Check if origin is a subdomain of frontend domain
	// Example: frontendDomain="balansi.me", originHost="demo.balansi.me" -> valid
	// Example: frontendDomain="demo.balansi.me", originHost="demo.balansi.me" -> valid
	if strings.HasSuffix(originHost, "."+normalizedFrontendDomain) {
		return requestOrigin
	}

	// Origin doesn't match configured frontend domain
	log.Printf("Origin '%s' does not match configured FRONTEND_DOMAIN '%s'", requestOrigin, frontendDomain)
	return ""
}

// addCORSHeaders adds CORS headers to the response
// When using credentials: 'include', we must use specific origin, not '*'
// Validates origin against FRONTEND_DOMAIN if configured
func addCORSHeaders(resp events.APIGatewayV2HTTPResponse, origin string) events.APIGatewayV2HTTPResponse {
	if resp.Headers == nil {
		resp.Headers = make(map[string]string)
	}

	// Validate origin against FRONTEND_DOMAIN if configured
	validatedOrigin := validateOrigin(origin)

	// When using credentials: 'include', we MUST use specific origin, not '*'
	// If origin is empty or invalid, use wildcard but don't set credentials header
	// In practice, browsers always send Origin header with credentials: 'include'
	if validatedOrigin == "" {
		validatedOrigin = "*"
	}

	resp.Headers["Access-Control-Allow-Origin"] = validatedOrigin
	resp.Headers["Access-Control-Allow-Methods"] = "GET, POST, OPTIONS"
	resp.Headers["Access-Control-Allow-Headers"] = "Content-Type, Authorization"

	// Only add credentials header when origin is specific (not wildcard)
	// This is REQUIRED when frontend uses credentials: 'include'
	// Browsers reject responses with Access-Control-Allow-Credentials: true and Access-Control-Allow-Origin: *
	if validatedOrigin != "*" && validatedOrigin != "" {
		resp.Headers["Access-Control-Allow-Credentials"] = "true"
	}

	return resp
}

func methodNotAllowedResponse(origin string) events.APIGatewayV2HTTPResponse {
	resp := events.APIGatewayV2HTTPResponse{
		StatusCode: 405,
		Headers: map[string]string{
			"Content-Type": "application/json",
		},
		Body: `{"error": "Method not allowed"}`,
	}
	return addCORSHeaders(resp, origin)
}

func handler(ctx context.Context, req events.APIGatewayV2HTTPRequest) (events.APIGatewayV2HTTPResponse, error) {
	log.Printf("Received request: RawPath='%s', Path='%s', Method='%s'",
		req.RawPath, req.RequestContext.HTTP.Path, req.RequestContext.HTTP.Method)

	// Get origin from request headers (check multiple variations)
	origin := req.Headers["origin"]
	if origin == "" {
		origin = req.Headers["Origin"]
	}
	if origin == "" {
		origin = req.Headers["ORIGIN"]
	}

	// Log origin for debugging
	log.Printf("Request origin: '%s'", origin)

	// Validate origin against FRONTEND_DOMAIN if configured
	// For preflight OPTIONS requests, we still need to validate but allow them to proceed
	// For actual requests, reject if origin doesn't match (but allow requests without Origin header, like curl)
	if req.RequestContext.HTTP.Method != "OPTIONS" {
		frontendDomain := os.Getenv("FRONTEND_DOMAIN")
		if origin != "" && frontendDomain != "" {
			// Only validate if Origin header is present
			// Requests without Origin (like curl) are allowed
			validatedOrigin := validateOrigin(origin)
			if validatedOrigin == "" {
				// Origin validation failed and FRONTEND_DOMAIN is configured
				// Reject the request with CORS headers to avoid CORS errors in browser
				resp := events.APIGatewayV2HTTPResponse{
					StatusCode: 403,
					Headers: map[string]string{
						"Content-Type": "application/json",
					},
					Body: `{"error": "Origin not allowed"}`,
				}
				return addCORSHeaders(resp, origin), nil
			}
			// Use validated origin
			origin = validatedOrigin
		}
	}

	// Simple routing based on path
	path := req.RequestContext.HTTP.Path
	if path == "" {
		path = req.RawPath
	}

	// Strip stage from path if present
	stage := os.Getenv("STAGE")
	if stage != "" {
		prefix := "/" + stage
		path = strings.TrimPrefix(path, prefix)
	}

	// Handle CORS preflight requests
	if req.RequestContext.HTTP.Method == "OPTIONS" {
		resp := events.APIGatewayV2HTTPResponse{
			StatusCode: 200,
			Headers:    make(map[string]string),
			Body:       "",
		}
		return addCORSHeaders(resp, origin), nil
	}

	// Add GET method to CORS headers
	resp := addCORSHeaders(events.APIGatewayV2HTTPResponse{}, origin)
	if resp.Headers == nil {
		resp.Headers = make(map[string]string)
	}
	resp.Headers["Access-Control-Allow-Methods"] = "GET, POST, OPTIONS"

	switch path {
	case "/auth/sign-up":
		if req.RequestContext.HTTP.Method == "POST" {
			resp, err := signupHandler.Handle(ctx, req)
			if err != nil {
				return resp, err
			}
			return addCORSHeaders(resp, origin), nil
		}
		return methodNotAllowedResponse(origin), nil
	case "/auth/confirm":
		if req.RequestContext.HTTP.Method == "POST" {
			resp, err := confirmHandler.Handle(ctx, req)
			if err != nil {
				return resp, err
			}
			return addCORSHeaders(resp, origin), nil
		}
		return methodNotAllowedResponse(origin), nil
	case "/auth/refresh":
		if req.RequestContext.HTTP.Method == "POST" {
			resp, err := refreshHandler.Handle(ctx, req)
			if err != nil {
				return resp, err
			}
			return addCORSHeaders(resp, origin), nil
		}
		return methodNotAllowedResponse(origin), nil
	case "/auth/me":
		if req.RequestContext.HTTP.Method == "GET" {
			resp, err := meHandler.Handle(ctx, req)
			if err != nil {
				return resp, err
			}
			return addCORSHeaders(resp, origin), nil
		}
		return methodNotAllowedResponse(origin), nil
	default:
		resp := events.APIGatewayV2HTTPResponse{
			StatusCode: 404,
			Headers: map[string]string{
				"Content-Type": "application/json",
			},
			Body: `{"error": "Not found", "path": "` + path + `"}`,
		}
		return addCORSHeaders(resp, origin), nil
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
			// Fallback: try to get from Referer header or use default dev server URL
			referer := r.Header.Get("Referer")
			if referer != "" {
				// Extract origin from referer (e.g., "http://localhost:5173/path" -> "http://localhost:5173")
				if idx := strings.Index(referer, "://"); idx != -1 {
					if pathIdx := strings.Index(referer[idx+3:], "/"); pathIdx != -1 {
						origin = referer[:idx+3+pathIdx]
					} else {
						origin = referer
					}
				}
			}
			// Default to common SvelteKit dev server URL if still empty
			if origin == "" {
				origin = "http://localhost:5173"
			}
		}

		// Validate origin against FRONTEND_DOMAIN if configured
		validatedOrigin := validateOrigin(origin)
		if validatedOrigin == "" && os.Getenv("FRONTEND_DOMAIN") != "" {
			// Origin validation failed and FRONTEND_DOMAIN is configured
			// Reject the request
			w.Header().Set("Access-Control-Allow-Origin", "*")
			w.WriteHeader(403)
			w.Write([]byte(`{"error": "Origin not allowed"}`))
			return
		}
		// Use validated origin or fallback to original origin
		if validatedOrigin != "" {
			origin = validatedOrigin
		}

		// Handle CORS preflight
		if r.Method == "OPTIONS" {
			if origin == "" {
				origin = "*"
			}
			w.Header().Set("Access-Control-Allow-Origin", origin)
			w.Header().Set("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
			w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization")
			if origin != "*" && origin != "" {
				w.Header().Set("Access-Control-Allow-Credentials", "true")
			}
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
		if origin == "" {
			origin = "*"
		}
		w.Header().Set("Access-Control-Allow-Origin", origin)
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization")
		if origin != "*" && origin != "" {
			w.Header().Set("Access-Control-Allow-Credentials", "true")
		}

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
	http.HandleFunc("/auth/refresh", handlerFunc)
	http.HandleFunc("/auth/me", handlerFunc)

	log.Printf("Server starting on port %s", port)
	log.Printf("Test endpoint: POST http://localhost:%s/auth/sign-up", port)
	log.Printf("Test endpoint: POST http://localhost:%s/auth/confirm", port)
	log.Printf("Test endpoint: POST http://localhost:%s/auth/refresh", port)
	log.Printf("Test endpoint: GET http://localhost:%s/auth/me", port)
	log.Printf("Test endpoint: GET http://localhost:%s/auth/me", port)
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
