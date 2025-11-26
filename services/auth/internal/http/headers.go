package http

import (
	"github.com/aws/aws-lambda-go/events"
)

// AddCORSHeaders adds CORS headers to the response
// When using credentials: 'include', we must use specific origin, not '*'
// Validates origin against FRONTEND_DOMAIN if configured
func AddCORSHeaders(resp events.APIGatewayV2HTTPResponse, origin string) events.APIGatewayV2HTTPResponse {
	if resp.Headers == nil {
		resp.Headers = make(map[string]string)
	}

	// Validate origin against FRONTEND_DOMAIN if configured
	validatedOrigin := ValidateOrigin(origin)

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

// MethodNotAllowedResponse creates a 405 Method Not Allowed response with CORS headers
func MethodNotAllowedResponse(origin string) events.APIGatewayV2HTTPResponse {
	resp := events.APIGatewayV2HTTPResponse{
		StatusCode: 405,
		Headers: map[string]string{
			"Content-Type": "application/json",
		},
		Body: `{"error": "Method not allowed"}`,
	}
	return AddCORSHeaders(resp, origin)
}

// OriginNotAllowedResponse creates a 403 Forbidden response for invalid origins with CORS headers
func OriginNotAllowedResponse(origin string) events.APIGatewayV2HTTPResponse {
	resp := events.APIGatewayV2HTTPResponse{
		StatusCode: 403,
		Headers: map[string]string{
			"Content-Type": "application/json",
		},
		Body: `{"error": "Origin not allowed"}`,
	}
	return AddCORSHeaders(resp, origin)
}
