package http

import (
	"os"
	"testing"

	"github.com/aws/aws-lambda-go/events"
	"github.com/stretchr/testify/assert"
)

// Helper functions for DRY testing

// assertCORSHeaders verifies that all required CORS headers are present in the response
func assertCORSHeaders(t *testing.T, headers map[string]string) {
	t.Helper()
	expectedCORSHeaders := []string{
		"Access-Control-Allow-Origin",
		"Access-Control-Allow-Methods",
		"Access-Control-Allow-Headers",
	}

	for _, header := range expectedCORSHeaders {
		_, exists := headers[header]
		assert.True(t, exists, "CORS header %s should exist", header)
	}
}

// assertErrorResponse verifies basic error response structure
func assertErrorResponse(t *testing.T, resp events.APIGatewayV2HTTPResponse, expectedStatus int, expectedBody string) {
	t.Helper()
	assert.Equal(t, expectedStatus, resp.StatusCode)
	assert.Equal(t, expectedBody, resp.Body)

	contentType, exists := resp.Headers["Content-Type"]
	assert.True(t, exists, "Content-Type header should exist")
	assert.Equal(t, "application/json", contentType)

	assertCORSHeaders(t, resp.Headers)
}

// withEnvVar temporarily sets an environment variable and returns a cleanup function
func withEnvVar(key, value string) func() {
	originalValue := os.Getenv(key)
	os.Setenv(key, value)
	return func() {
		if originalValue == "" {
			os.Unsetenv(key)
		} else {
			os.Setenv(key, originalValue)
		}
	}
}

// expectedCORSHeaders generates expected CORS headers map
func expectedCORSHeaders(origin string, includeCredentials bool, extraHeaders map[string]string) map[string]string {
	headers := map[string]string{
		"Access-Control-Allow-Origin":  origin,
		"Access-Control-Allow-Methods": "GET, POST, OPTIONS",
		"Access-Control-Allow-Headers": "Content-Type, Authorization",
	}

	if includeCredentials {
		headers["Access-Control-Allow-Credentials"] = "true"
	}

	// Add any extra headers (like Content-Type, Custom-Header from initial response)
	for k, v := range extraHeaders {
		headers[k] = v
	}

	return headers
}

// assertExpectedHeaders verifies that all expected headers are present with correct values
func assertExpectedHeaders(t *testing.T, actualHeaders map[string]string, expectedHeaders map[string]string) {
	t.Helper()
	for key, expectedValue := range expectedHeaders {
		actualValue, exists := actualHeaders[key]
		assert.True(t, exists, "Header %s should exist", key)
		assert.Equal(t, expectedValue, actualValue, "Header %s value should match", key)
	}
}

// assertNoUnexpectedHeaders verifies that no unexpected headers are present
func assertNoUnexpectedHeaders(t *testing.T, actualHeaders map[string]string, expectedHeaders map[string]string, allowedExtraHeaders []string) {
	t.Helper()
	// Build complete list of allowed headers
	allowedHeaders := make([]string, 0, len(expectedHeaders)+len(allowedExtraHeaders))
	for key := range expectedHeaders {
		allowedHeaders = append(allowedHeaders, key)
	}
	allowedHeaders = append(allowedHeaders, allowedExtraHeaders...)

	for key := range actualHeaders {
		assert.Contains(t, allowedHeaders, key, "Unexpected header %s", key)
	}
}

func TestAddCORSHeaders(t *testing.T) {
	tests := []struct {
		name               string
		origin             string
		frontendDomain     string
		initialResp        events.APIGatewayV2HTTPResponse
		expectedOrigin     string
		includeCredentials bool
		extraHeaders       map[string]string
	}{
		{
			name:           "Valid origin with FRONTEND_DOMAIN configured",
			origin:         "https://balansi.me",
			frontendDomain: "balansi.me",
			initialResp: events.APIGatewayV2HTTPResponse{
				StatusCode: 200,
			},
			expectedOrigin:     "https://balansi.me",
			includeCredentials: true,
		},
		{
			name:           "Valid subdomain origin",
			origin:         "https://demo.balansi.me",
			frontendDomain: "balansi.me",
			initialResp: events.APIGatewayV2HTTPResponse{
				StatusCode: 200,
			},
			expectedOrigin:     "https://demo.balansi.me",
			includeCredentials: true,
		},
		{
			name:           "Invalid origin uses wildcard without credentials",
			origin:         "https://evil.com",
			frontendDomain: "balansi.me",
			initialResp: events.APIGatewayV2HTTPResponse{
				StatusCode: 200,
			},
			expectedOrigin:     "*",
			includeCredentials: false,
		},
		{
			name:           "Empty origin uses wildcard without credentials",
			origin:         "",
			frontendDomain: "balansi.me",
			initialResp: events.APIGatewayV2HTTPResponse{
				StatusCode: 200,
			},
			expectedOrigin:     "*",
			includeCredentials: false,
		},
		{
			name:   "No FRONTEND_DOMAIN configured accepts origin",
			origin: "https://any-origin.com",
			initialResp: events.APIGatewayV2HTTPResponse{
				StatusCode: 200,
			},
			expectedOrigin:     "https://any-origin.com",
			includeCredentials: true,
		},
		{
			name:           "Response with existing headers preserves them",
			origin:         "https://balansi.me",
			frontendDomain: "balansi.me",
			initialResp: events.APIGatewayV2HTTPResponse{
				StatusCode: 200,
				Headers: map[string]string{
					"Content-Type":  "application/json",
					"Custom-Header": "value",
				},
			},
			expectedOrigin:     "https://balansi.me",
			includeCredentials: true,
			extraHeaders: map[string]string{
				"Content-Type":  "application/json",
				"Custom-Header": "value",
			},
		},
		{
			name:           "Response with nil headers initializes them",
			origin:         "https://balansi.me",
			frontendDomain: "balansi.me",
			initialResp: events.APIGatewayV2HTTPResponse{
				StatusCode: 200,
				Headers:    nil,
			},
			expectedOrigin:     "https://balansi.me",
			includeCredentials: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			// Set up environment with cleanup
			var cleanup func()
			if tt.frontendDomain != "" {
				cleanup = withEnvVar("FRONTEND_DOMAIN", tt.frontendDomain)
				defer cleanup()
			}

			got := AddCORSHeaders(tt.initialResp, tt.origin)
			wantHeaders := expectedCORSHeaders(tt.expectedOrigin, tt.includeCredentials, tt.extraHeaders)

			// Check all expected headers are present with correct values
			assertExpectedHeaders(t, got.Headers, wantHeaders)

			// Check no unexpected headers are present (excluding known extra headers from initial response)
			allowedExtraHeaders := []string{"Content-Type", "Custom-Header"}
			assertNoUnexpectedHeaders(t, got.Headers, wantHeaders, allowedExtraHeaders)
		})
	}
}

func TestMethodNotAllowedResponse(t *testing.T) {
	tests := []struct {
		name   string
		origin string
	}{
		{
			name:   "Valid origin",
			origin: "https://balansi.me",
		},
		{
			name:   "Empty origin",
			origin: "",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := MethodNotAllowedResponse(tt.origin)
			assertErrorResponse(t, got, 405, `{"error": "Method not allowed"}`)
		})
	}
}

func TestOriginNotAllowedResponse(t *testing.T) {
	tests := []struct {
		name   string
		origin string
	}{
		{
			name:   "Valid origin",
			origin: "https://balansi.me",
		},
		{
			name:   "Empty origin",
			origin: "",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := OriginNotAllowedResponse(tt.origin)
			assertErrorResponse(t, got, 403, `{"error": "Origin not allowed"}`)
		})
	}
}
