package http

import (
	"context"

	"github.com/aws/aws-lambda-go/events"
)

// HandlerFunc represents a handler function
type HandlerFunc func(ctx context.Context, req events.APIGatewayV2HTTPRequest) (events.APIGatewayV2HTTPResponse, error)

// RouteConfig defines a route configuration
type RouteConfig struct {
	Path    string
	Method  string
	Handler HandlerFunc
}

// HandlerRegistry holds references to all HTTP handlers and route configurations
type HandlerRegistry struct {
	SignupHandler         HandlerFunc
	ConfirmHandler        HandlerFunc
	RefreshHandler        HandlerFunc
	MeHandler             HandlerFunc
	ForgotPasswordHandler HandlerFunc
	ResetPasswordHandler  HandlerFunc
	LogoutHandler         HandlerFunc
	Routes                []RouteConfig
}

// NewHandlerRegistry creates a new handler registry with predefined routes
func NewHandlerRegistry() *HandlerRegistry {
	registry := &HandlerRegistry{
		Routes: []RouteConfig{
			{Path: "/auth/sign-up", Method: "POST"},
			{Path: "/auth/confirm", Method: "POST"},
			{Path: "/auth/refresh", Method: "POST"},
			{Path: "/auth/me", Method: "GET"},
			{Path: "/auth/forgot-password", Method: "POST"},
			{Path: "/auth/reset-password", Method: "POST"},
			{Path: "/auth/logout", Method: "POST"},
		},
	}
	return registry
}

// ProcessHTTPCORSOptions handles CORS preflight OPTIONS requests for HTTP responses
func ProcessHTTPCORSOptions(origin string) map[string]string {
	headers := map[string]string{
		"Access-Control-Allow-Origin":  origin,
		"Access-Control-Allow-Methods": "GET, POST, OPTIONS",
		"Access-Control-Allow-Headers": "Content-Type, Authorization",
	}

	// Only add credentials header when origin is specific (not wildcard)
	if origin != "*" && origin != "" {
		headers["Access-Control-Allow-Credentials"] = "true"
	}

	return headers
}

// HandleLambdaRequest handles Lambda requests using unified processing utilities
func HandleLambdaRequest(ctx context.Context, req events.APIGatewayV2HTTPRequest, frontendDomain string, handlers *HandlerRegistry) (events.APIGatewayV2HTTPResponse, error) {
	// Adapt Lambda request to common interface
	adapter := NewLambdaRequestAdapter(req)

	// Validate origin
	origin, err := ProcessOriginValidation(adapter, frontendDomain)
	if err != nil {
		return OriginNotAllowedResponse(origin), nil
	}

	// Extract and normalize request path
	path := ExtractRequestPath(req, "") // TODO: Pass stage from config

	// Handle CORS preflight requests
	if req.RequestContext.HTTP.Method == "OPTIONS" {
		response := ProcessCORSOptions(origin)
		return response.ToLambdaResponse(), nil
	}

	// Route the request
	return routeRequest(ctx, req, path, origin, handlers), nil
}

// routeRequest processes the request based on path and method using the registry
func routeRequest(ctx context.Context, req events.APIGatewayV2HTTPRequest, path, origin string, handlers *HandlerRegistry) events.APIGatewayV2HTTPResponse {
	// Find the route configuration
	var routeConfig *RouteConfig
	for _, route := range handlers.Routes {
		if route.Path == path {
			routeConfig = &route
			break
		}
	}

	if routeConfig == nil {
		// Route not found
		resp := events.APIGatewayV2HTTPResponse{
			StatusCode: 404,
			Headers: map[string]string{
				"Content-Type": "application/json",
			},
			Body: `{"error": "Not found", "path": "` + path + `"}`,
		}
		return AddCORSHeaders(resp, origin)
	}

	// Get the appropriate handler
	var handler HandlerFunc
	switch path {
	case "/auth/sign-up":
		handler = handlers.SignupHandler
	case "/auth/confirm":
		handler = handlers.ConfirmHandler
	case "/auth/refresh":
		handler = handlers.RefreshHandler
	case "/auth/me":
		handler = handlers.MeHandler
	case "/auth/forgot-password":
		handler = handlers.ForgotPasswordHandler
	case "/auth/reset-password":
		handler = handlers.ResetPasswordHandler
	case "/auth/logout":
		handler = handlers.LogoutHandler
	}

	// Check method and call handler
	if req.RequestContext.HTTP.Method == routeConfig.Method && handler != nil {
		resp, err := handler(ctx, req)
		if err != nil {
			return resp // Handler already returns proper response on error
		}
		return AddCORSHeaders(resp, origin)
	}

	return MethodNotAllowedResponse(origin)
}
