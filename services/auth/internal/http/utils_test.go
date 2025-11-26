package http

import (
	"net/http"
	"os"
	"testing"

	"github.com/aws/aws-lambda-go/events"
	"github.com/stretchr/testify/assert"
)

// Helper functions for DRY testing

// runSimpleStringTests runs table-driven tests with simple string args
func runSimpleStringTests(t *testing.T, tests []struct {
	name   string
	header string
	want   string
}, testFunc func(string) string) {
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := testFunc(tt.header)
			assert.Equal(t, tt.want, got)
		})
	}
}

// runMapStringTests runs table-driven tests with map[string]string args
func runMapStringTests(t *testing.T, tests []struct {
	name    string
	headers map[string]string
	want    string
}, testFunc func(map[string]string) string) {
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := testFunc(tt.headers)
			assert.Equal(t, tt.want, got)
		})
	}
}

// runCookieTests runs table-driven tests for cookie extraction
func runCookieTests(t *testing.T, tests []struct {
	name       string
	cookieName string
	cookies    []string
	want       string
}, testFunc func([]string, string) string) {
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := testFunc(tt.cookies, tt.cookieName)
			assert.Equal(t, tt.want, got)
		})
	}
}

// runCookieHeaderTests runs table-driven tests for cookie header building
func runCookieHeaderTests(t *testing.T, tests []struct {
	name         string
	key          string
	value        string
	reqDomain    string
	origin       string
	wantContains []string
}) {
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			req := createAPIGatewayRequest(map[string]string{"Origin": tt.origin}, tt.reqDomain)
			got := BuildCookieHeader(tt.value, tt.key, req)
			for _, want := range tt.wantContains {
				assert.Contains(t, got, want)
			}
		})
	}
}

// runDomainTests runs table-driven tests for domain functions
func runDomainTests(t *testing.T, tests []struct {
	name    string
	domain1 string
	domain2 string
	want    string
}, testFunc func(string, string) string) {
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := testFunc(tt.domain1, tt.domain2)
			assert.Equal(t, tt.want, got)
		})
	}
}

// runOriginDomainTests runs table-driven tests for origin+domain functions
func runOriginDomainTests(t *testing.T, tests []struct {
	name      string
	origin    string
	apiDomain string
	want      string
}, testFunc func(string, string) string) {
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := testFunc(tt.origin, tt.apiDomain)
			assert.Equal(t, tt.want, got)
		})
	}
}

// runEnvDomainTests runs table-driven tests with environment variables
func runEnvDomainTests(t *testing.T, tests []struct {
	name      string
	origin    string
	apiDomain string
	env       map[string]string
	want      string
}) {
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			// Set env vars
			for k, v := range tt.env {
				os.Setenv(k, v)
			}
			// Cleanup
			defer func() {
				for k := range tt.env {
					os.Unsetenv(k)
				}
			}()

			got := getCookieDomain(tt.origin, tt.apiDomain)
			assert.Equal(t, tt.want, got)
		})
	}
}

// runPathTests runs table-driven tests for path extraction
func runPathTests(t *testing.T, tests []struct {
	name     string
	httpPath string
	rawPath  string
	stage    string
	want     string
}) {
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			req := createAPIGatewayRequestWithPath(tt.httpPath, tt.rawPath, tt.stage)
			got := ExtractRequestPath(req, tt.stage)
			assert.Equal(t, tt.want, got)
		})
	}
}

// createAPIGatewayRequest creates a basic APIGatewayV2HTTPRequest for testing
func createAPIGatewayRequest(headers map[string]string, domain string) events.APIGatewayV2HTTPRequest {
	return events.APIGatewayV2HTTPRequest{
		Headers: headers,
		RequestContext: events.APIGatewayV2HTTPRequestContext{
			DomainName: domain,
		},
	}
}

// createAPIGatewayRequestWithPath creates an APIGatewayV2HTTPRequest with path information
func createAPIGatewayRequestWithPath(httpPath, rawPath, stage string) events.APIGatewayV2HTTPRequest {
	return events.APIGatewayV2HTTPRequest{
		RequestContext: events.APIGatewayV2HTTPRequestContext{
			HTTP: events.APIGatewayV2HTTPRequestContextHTTPDescription{
				Path: httpPath,
			},
		},
		RawPath: rawPath,
	}
}

// withEnvVars temporarily sets environment variables and returns cleanup function
func withEnvVars(env map[string]string) func() {
	for k, v := range env {
		os.Setenv(k, v)
	}
	return func() {
		for k := range env {
			os.Unsetenv(k)
		}
	}
}

func TestExtractBearerToken(t *testing.T) {
	tests := []struct {
		name   string
		header string
		want   string
	}{
		{"Valid Bearer Token", "Bearer valid.token.123", "valid.token.123"},
		{"Case Insensitive Bearer", "bearer valid.token.123", "valid.token.123"},
		{"Missing Bearer Prefix", "valid.token.123", ""},
		{"Empty Header", "", ""},
		{"Just Bearer", "Bearer ", ""},
	}

	runSimpleStringTests(t, tests, ExtractBearerToken)
}

func TestExtractOrigin(t *testing.T) {
	tests := []struct {
		name    string
		headers map[string]string
		want    string
	}{
		{"lowercase origin", map[string]string{"origin": "https://example.com"}, "https://example.com"},
		{"capital Origin", map[string]string{"Origin": "https://example.com"}, "https://example.com"},
		{"uppercase ORIGIN", map[string]string{"ORIGIN": "https://example.com"}, "https://example.com"},
		{"multiple origins - lowercase takes precedence", map[string]string{
			"origin": "https://lowercase.com",
			"Origin": "https://capital.com",
			"ORIGIN": "https://uppercase.com",
		}, "https://lowercase.com"},
		{"no origin headers", map[string]string{"content-type": "application/json"}, ""},
		{"empty headers map", map[string]string{}, ""},
	}

	runMapStringTests(t, tests, func(headers map[string]string) string {
		req := createAPIGatewayRequest(headers, "")
		return ExtractOrigin(req)
	})
}

func TestExtractCookieValue(t *testing.T) {
	tests := []struct {
		name       string
		cookieName string
		cookies    []string
		want       string
	}{
		{"Valid Cookie", "session_id", []string{"session_id=12345; Path=/"}, "12345"},
		{"Multiple Cookies", "auth", []string{"theme=dark", "auth=token123; other=value"}, "token123"},
		{"Cookie Not Found", "missing", []string{"session_id=12345"}, ""},
		{"Empty Header", "session_id", []string{}, ""},
	}

	runCookieTests(t, tests, ExtractCookieValue)
}

func TestLocalRequestAdapter_GetCookies(t *testing.T) {
	tests := []struct {
		name     string
		cookies  []*http.Cookie
		expected []string
	}{
		{
			name: "Single Cookie",
			cookies: []*http.Cookie{
				{Name: "session_id", Value: "abc123"},
			},
			expected: []string{"session_id=abc123"},
		},
		{
			name: "Multiple Cookies",
			cookies: []*http.Cookie{
				{Name: "session_id", Value: "abc123"},
				{Name: "theme", Value: "dark"},
			},
			expected: []string{"session_id=abc123", "theme=dark"},
		},
		{
			name:     "No Cookies",
			cookies:  []*http.Cookie{},
			expected: []string{},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			// Create HTTP request
			req, _ := http.NewRequest("GET", "/", nil)

			// Add cookies to request
			for _, cookie := range tt.cookies {
				req.AddCookie(cookie)
			}

			// Create adapter
			adapter := NewLocalRequestAdapter(req)

			// Test GetCookies
			result := adapter.GetCookies()
			assert.Equal(t, tt.expected, result)
		})
	}
}

func TestBuildCookieHeader(t *testing.T) {
	tests := []struct {
		name         string
		key          string
		value        string
		reqDomain    string
		origin       string
		wantContains []string
	}{
		{"Standard Production Cookie", "session", "123", "api.example.com", "https://app.example.com", []string{
			"session=123",
			"Max-Age=2592000",
			"HttpOnly",
			"Secure",
			"SameSite=None",
			"Domain=.example.com",
		}},
		{"Localhost", "session", "123", "localhost", "http://localhost:3000", []string{
			"session=123",
			"SameSite=Lax",
		}},
	}

	runCookieHeaderTests(t, tests)
}

func TestGetCookieDomain(t *testing.T) {
	tests := []struct {
		name      string
		origin    string
		apiDomain string
		env       map[string]string
		want      string
	}{
		{
			name:      "Same Domain",
			origin:    "https://example.com",
			apiDomain: "example.com",
			want:      "",
		},
		{
			name:      "Subdomain Origin",
			origin:    "https://app.example.com",
			apiDomain: "api.example.com",
			want:      ".example.com",
		},
		{
			name:      "Explicit COOKIE_DOMAIN",
			origin:    "https://google.com",
			apiDomain: "example.com",
			env:       map[string]string{"COOKIE_DOMAIN": ".custom.com"},
			want:      ".custom.com",
		},
		{
			name:      "COOKIE_DOMAIN without dot",
			origin:    "https://google.com",
			apiDomain: "example.com",
			env:       map[string]string{"COOKIE_DOMAIN": "custom.com"},
			want:      ".custom.com",
		},
		{
			name:      "FRONTEND and API DOMAIN env",
			origin:    "",
			apiDomain: "",
			env:       map[string]string{"FRONTEND_DOMAIN": "app.env.com", "API_DOMAIN": "api.env.com"},
			want:      ".env.com",
		},
	}

	runEnvDomainTests(t, tests)
}

func TestExtractSharedDomainFromStrings(t *testing.T) {
	tests := []struct {
		name    string
		domain1 string
		domain2 string
		want    string
	}{
		{"Common TLD+1", "app.example.com", "api.example.com", ".example.com"},
		{"No Common", "google.com", "example.com", ""},
		{"Same Domain", "example.com", "example.com", ""},
		{"Localhost", "localhost", "localhost", ""},
		{"Empty", "", "", ""},
		{"One Empty", "example.com", "", ""},
		{"With Port", "example.com:8080", "api.example.com:9000", ".example.com"},
	}

	runDomainTests(t, tests, extractSharedDomainFromStrings)
}

func TestExtractSharedDomain(t *testing.T) {
	tests := []struct {
		name      string
		origin    string
		apiDomain string
		want      string
	}{
		{"Standard", "https://app.example.com", "api.example.com", ".example.com"},
		{"Invalid URL", ":/invalid", "api.example.com", ""},
		{"Empty", "", "", ""},
	}

	runOriginDomainTests(t, tests, extractSharedDomain)
}

func TestExtractRequestPath(t *testing.T) {
	tests := []struct {
		name     string
		httpPath string
		rawPath  string
		stage    string
		want     string
	}{
		{"HTTP Path with stage", "/prod/auth/sign-up", "/prod/auth/sign-up", "prod", "/auth/sign-up"},
		{"Raw path fallback", "", "/auth/me", "", "/auth/me"},
		{"No stage prefix", "/auth/confirm", "/auth/confirm", "", "/auth/confirm"},
		{"Stage with multiple path segments", "/bal-7/auth/refresh", "/bal-7/auth/refresh", "bal-7", "/auth/refresh"},
	}

	runPathTests(t, tests)
}
