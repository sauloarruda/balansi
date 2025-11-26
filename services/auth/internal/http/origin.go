package http

import (
	"errors"
	"log"
	"net/url"
	"os"
	"strings"

	"github.com/aws/aws-lambda-go/events"
)

// normalizeHost removes port from host if present
// Example: "example.com:3000" -> "example.com"
func normalizeHost(host string) string {
	if idx := strings.Index(host, ":"); idx != -1 {
		return host[:idx]
	}
	return host
}

// normalizeDomain removes protocol and port from domain if present
// Example: "https://example.com:3000" -> "example.com"
func normalizeDomain(domain string) string {
	// Remove protocol
	if idx := strings.Index(domain, "://"); idx != -1 {
		domain = domain[idx+3:]
	}
	// Remove port
	return normalizeHost(domain)
}

// ValidateOrigin validates the origin against frontendDomain if configured
// Returns the validated origin or empty string if validation fails
// If frontendDomain is not provided, falls back to FRONTEND_DOMAIN environment variable
func ValidateOrigin(requestOrigin string, frontendDomain ...string) string {
	// If no origin in request, return empty (will be handled by caller)
	if requestOrigin == "" {
		return ""
	}

	// Use provided frontendDomain or get from environment
	var domain string
	if len(frontendDomain) > 0 && frontendDomain[0] != "" {
		domain = frontendDomain[0]
	} else {
		domain = os.Getenv("FRONTEND_DOMAIN")
	}

	if domain == "" {
		// No frontend domain configured, accept any origin (fallback behavior)
		return requestOrigin
	}

	// Parse request origin URL
	originURL, err := url.Parse(requestOrigin)
	if err != nil || originURL.Host == "" {
		log.Printf("Invalid origin URL: %s", requestOrigin)
		return ""
	}

	// Validate scheme (only allow http/https)
	if originURL.Scheme != "http" && originURL.Scheme != "https" {
		log.Printf("Invalid origin scheme '%s': %s", originURL.Scheme, requestOrigin)
		return ""
	}

	originHost := normalizeHost(originURL.Host)
	normalizedDomain := normalizeDomain(domain)

	// Check if origin matches frontend domain exactly
	if originHost == normalizedDomain {
		return requestOrigin
	}

	// Check if origin is a subdomain of frontend domain
	// Example: domain="balansi.me", originHost="demo.balansi.me" -> valid
	// Example: domain="demo.balansi.me", originHost="demo.balansi.me" -> valid
	if strings.HasSuffix(originHost, "."+normalizedDomain) {
		return requestOrigin
	}

	// Origin doesn't match configured frontend domain
	log.Printf("Origin '%s' does not match configured frontend domain '%s'", requestOrigin, domain)
	return ""
}

// ProcessOriginValidation validates the request origin and returns the validated origin or an error
func ProcessOriginValidation(req HTTPRequest, frontendDomain string) (string, error) {
	origin := req.GetOrigin()

	// Only validate non-OPTIONS requests
	if req.GetMethod() == "OPTIONS" {
		return origin, nil
	}

	if origin != "" && frontendDomain != "" {
		validatedOrigin := ValidateOrigin(origin, frontendDomain)
		if validatedOrigin == "" {
			return "", errors.New("origin not allowed")
		}
		return validatedOrigin, nil
	}

	return origin, nil
}

// ProcessCORSOptions handles CORS preflight OPTIONS requests
func ProcessCORSOptions(origin string) HTTPResponse {
	// Create a dummy response to leverage AddCORSHeaders validation logic
	dummyResp := events.APIGatewayV2HTTPResponse{
		StatusCode: 200,
		Headers: map[string]string{
			"Access-Control-Allow-Methods": "GET, POST, OPTIONS",
			"Access-Control-Allow-Headers": "Content-Type, Authorization",
		},
		Body: "",
	}

	// Use AddCORSHeaders to get proper validation and credentials handling
	corsResp := AddCORSHeaders(dummyResp, origin)

	return HTTPResponse{
		StatusCode: corsResp.StatusCode,
		Headers:    corsResp.Headers,
		Body:       corsResp.Body,
	}
}
