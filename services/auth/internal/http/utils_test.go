package http

import (
	"os"
	"testing"

	"github.com/aws/aws-lambda-go/events"
	"github.com/stretchr/testify/assert"
)

func TestExtractBearerToken(t *testing.T) {
	tests := []struct {
		name   string
		header string
		want   string
	}{
		{
			name:   "Valid Bearer Token",
			header: "Bearer valid.token.123",
			want:   "valid.token.123",
		},
		{
			name:   "Case Insensitive Bearer",
			header: "bearer valid.token.123",
			want:   "valid.token.123",
		},
		{
			name:   "Missing Bearer Prefix",
			header: "valid.token.123",
			want:   "",
		},
		{
			name:   "Empty Header",
			header: "",
			want:   "",
		},
		{
			name:   "Just Bearer",
			header: "Bearer ",
			want:   "",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := ExtractBearerToken(tt.header)
			assert.Equal(t, tt.want, got)
		})
	}
}

func TestExtractCookieValue(t *testing.T) {
	tests := []struct {
		name       string
		cookieName string
		cookies    []string
		want       string
	}{
		{
			name:       "Valid Cookie",
			cookieName: "session_id",
			cookies:    []string{"session_id=12345; Path=/"},
			want:       "12345",
		},
		{
			name:       "Multiple Cookies",
			cookieName: "auth",
			cookies:    []string{"theme=dark", "auth=token123; other=value"},
			want:       "token123",
		},
		{
			name:       "Cookie Not Found",
			cookieName: "missing",
			cookies:    []string{"session_id=12345"},
			want:       "",
		},
		{
			name:       "Empty Header",
			cookieName: "session_id",
			cookies:    []string{},
			want:       "",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := ExtractCookieValue(tt.cookies, tt.cookieName)
			assert.Equal(t, tt.want, got)
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
		{
			name:      "Standard Production Cookie",
			key:       "session",
			value:     "123",
			reqDomain: "api.example.com",
			origin:    "https://app.example.com",
			wantContains: []string{
				"session=123",
				"Max-Age=2592000",
				"HttpOnly",
				"Secure",
				"SameSite=None",
				"Domain=.example.com",
			},
		},
		{
			name:      "Localhost",
			key:       "session",
			value:     "123",
			reqDomain: "localhost",
			origin:    "http://localhost:3000",
			wantContains: []string{
				"session=123",
				"SameSite=Lax",
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			req := events.APIGatewayV2HTTPRequest{
				RequestContext: events.APIGatewayV2HTTPRequestContext{
					DomainName: tt.reqDomain,
				},
				Headers: map[string]string{
					"Origin": tt.origin,
				},
			}

			got := BuildCookieHeader(tt.value, tt.key, req)
			for _, want := range tt.wantContains {
				assert.Contains(t, got, want)
			}
		})
	}
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

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			// Set env
			for k, v := range tt.env {
				os.Setenv(k, v)
			}
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

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := extractSharedDomainFromStrings(tt.domain1, tt.domain2)
			assert.Equal(t, tt.want, got)
		})
	}
}

func TestExtractSharedDomain(t *testing.T) {
	tests := []struct {
		name string
		origin string
		apiDomain string
		want string
	}{
		{"Standard", "https://app.example.com", "api.example.com", ".example.com"},
		{"Invalid URL", ":/invalid", "api.example.com", ""},
		{"Empty", "", "", ""},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := extractSharedDomain(tt.origin, tt.apiDomain)
			assert.Equal(t, tt.want, got)
		})
	}
}
