package http

import (
	"net/http"
	"os"
	"time"

	"services/auth/internal/logger"

	"github.com/aws/aws-lambda-go/events"
)

// LocalServer represents the local HTTP server
type LocalServer struct {
	server          *http.Server
	frontendDomain  string
	handlerRegistry *HandlerRegistry
}

// NewLocalServer creates a new local HTTP server instance
func NewLocalServer(port, frontendDomain string, handlerRegistry *HandlerRegistry) *LocalServer {
	if port == "" {
		port = "3000"
	}

	s := &LocalServer{
		frontendDomain:  frontendDomain,
		handlerRegistry: handlerRegistry,
	}

	mux := http.NewServeMux()
	// Single handler for all auth routes
	mux.HandleFunc("/auth/", s.handleRequest)

	s.server = &http.Server{
		Addr:              ":" + port,
		Handler:           mux,
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       10 * time.Second,
		WriteTimeout:      10 * time.Second,
		IdleTimeout:       60 * time.Second,
	}

	return s
}

// handleRequest processes local HTTP requests using unified logic
func (s *LocalServer) handleRequest(w http.ResponseWriter, r *http.Request) {
	// Adapt local request to common interface
	adapter := NewLocalRequestAdapter(r)

	// Validate origin
	origin, err := ProcessOriginValidation(adapter, s.frontendDomain)
	if err != nil {
		response := HTTPResponse{
			StatusCode: 403,
			Headers: map[string]string{
				"Content-Type": "application/json",
			},
			Body: `{"error": "Origin not allowed"}`,
		}
		response.WriteTo(w)
		return
	}

	// Handle CORS preflight requests
	if r.Method == "OPTIONS" {
		headers := ProcessHTTPCORSOptions(origin)
		for key, value := range headers {
			w.Header().Set(key, value)
		}
		w.WriteHeader(200)
		return
	}

	// Convert to Lambda request for handler compatibility
	lambdaReq := events.APIGatewayV2HTTPRequest{
		RawPath:        r.URL.Path,
		RawQueryString: r.URL.RawQuery,
		Body:           adapter.GetBody(),
		Headers:        adapter.GetHeaders(),
		Cookies:        adapter.GetCookies(),
		RequestContext: events.APIGatewayV2HTTPRequestContext{
			HTTP: events.APIGatewayV2HTTPRequestContextHTTPDescription{
				Method: r.Method,
				Path:   r.URL.Path,
			},
		},
	}

	// Route and handle the request
	lambdaResp := routeRequest(r.Context(), lambdaReq, r.URL.Path, origin, s.handlerRegistry)

	// For local development, provide helpful error messages
	if lambdaResp.StatusCode == 501 {
		lambdaResp = events.APIGatewayV2HTTPResponse{
			StatusCode: 200,
			Headers: map[string]string{
				"Content-Type": "application/json",
			},
			Body: `{"message": "Local server - use Lambda for actual handler execution", "endpoint": "` + r.URL.Path + `", "method": "` + r.Method + `"}`,
		}
	}

	// Convert to HTTPResponse and add CORS headers
	resp := HTTPResponse{
		StatusCode: lambdaResp.StatusCode,
		Headers:    lambdaResp.Headers,
		Body:       lambdaResp.Body,
	}

	// Write response
	resp.WriteTo(w)
}

// StartLocalServer starts the local development server
func StartLocalServer(handlerRegistry *HandlerRegistry) {
	port := os.Getenv("PORT")
	if port == "" {
		port = "3000"
	}

	frontendDomain := os.Getenv("FRONTEND_DOMAIN")

	logger.Info("Server starting on port %s", port)
	logger.Info("Local server for CORS testing - handlers return mock responses")
	logger.Info("Test endpoint: POST http://localhost:%s/auth/sign-up", port)
	logger.Info("Test endpoint: POST http://localhost:%s/auth/confirm", port)
	logger.Info("Test endpoint: POST http://localhost:%s/auth/refresh", port)
	logger.Info("Test endpoint: GET http://localhost:%s/auth/me", port)
	logger.Info("Test endpoint: POST http://localhost:%s/auth/forgot-password", port)
	logger.Info("Test endpoint: POST http://localhost:%s/auth/reset-password", port)
	logger.Info("Test endpoint: POST http://localhost:%s/auth/logout", port)

	server := NewLocalServer(port, frontendDomain, handlerRegistry)
	if err := server.ListenAndServe(); err != nil {
		logger.Error("Failed to start server: %v", err)
		os.Exit(1)
	}
}

// ListenAndServe starts the local HTTP server
func (s *LocalServer) ListenAndServe() error {
	return s.server.ListenAndServe()
}
