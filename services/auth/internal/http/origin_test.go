package http

import (
	"os"
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestValidateOrigin(t *testing.T) {
	tests := []struct {
		name           string
		requestOrigin  string
		frontendDomain string
		want           string
	}{
		{
			name:          "Empty origin returns empty",
			requestOrigin: "",
			want:          "",
		},
		{
			name:          "No FRONTEND_DOMAIN configured accepts any origin",
			requestOrigin: "https://evil.com",
			want:          "https://evil.com",
		},
		{
			name:           "Exact domain match",
			requestOrigin:  "https://balansi.me",
			frontendDomain: "balansi.me",
			want:           "https://balansi.me",
		},
		{
			name:           "Exact domain match with port",
			requestOrigin:  "https://balansi.me:443",
			frontendDomain: "balansi.me",
			want:           "https://balansi.me:443",
		},
		{
			name:           "Subdomain match",
			requestOrigin:  "https://demo.balansi.me",
			frontendDomain: "balansi.me",
			want:           "https://demo.balansi.me",
		},
		{
			name:           "Subdomain match with port",
			requestOrigin:  "https://demo.balansi.me:8080",
			frontendDomain: "balansi.me",
			want:           "https://demo.balansi.me:8080",
		},
		{
			name:           "Frontend domain with port configured",
			requestOrigin:  "https://demo.balansi.me",
			frontendDomain: "balansi.me:3000",
			want:           "https://demo.balansi.me",
		},
		{
			name:           "Frontend domain with protocol configured",
			requestOrigin:  "https://demo.balansi.me",
			frontendDomain: "https://balansi.me",
			want:           "https://demo.balansi.me",
		},
		{
			name:           "Origin doesn't match domain",
			requestOrigin:  "https://evil.com",
			frontendDomain: "balansi.me",
			want:           "",
		},
		{
			name:           "Origin is parent domain of configured domain",
			requestOrigin:  "https://balansi.me",
			frontendDomain: "demo.balansi.me",
			want:           "",
		},
		{
			name:           "Invalid URL format",
			requestOrigin:  ":/invalid",
			frontendDomain: "balansi.me",
			want:           "",
		},
		{
			name:           "Origin with different subdomain doesn't match",
			requestOrigin:  "https://api.balansi.me",
			frontendDomain: "demo.balansi.me",
			want:           "",
		},
		{
			name:           "Complex subdomain matching",
			requestOrigin:  "https://stage.demo.balansi.me",
			frontendDomain: "balansi.me",
			want:           "https://stage.demo.balansi.me",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			// Set up environment
			if tt.frontendDomain != "" {
				os.Setenv("FRONTEND_DOMAIN", tt.frontendDomain)
			}
			defer func() {
				os.Unsetenv("FRONTEND_DOMAIN")
			}()

			got := ValidateOrigin(tt.requestOrigin)
			assert.Equal(t, tt.want, got)
		})
	}
}

// Mock HTTPRequest for testing
type mockHTTPRequest struct {
	method string
	origin string
}

func (m *mockHTTPRequest) GetMethod() string { return m.method }
func (m *mockHTTPRequest) GetPath() string   { return "" }
func (m *mockHTTPRequest) GetHeaders() map[string]string {
	return map[string]string{"origin": m.origin}
}
func (m *mockHTTPRequest) GetBody() string      { return "" }
func (m *mockHTTPRequest) GetOrigin() string    { return m.origin }
func (m *mockHTTPRequest) GetCookies() []string { return []string{} }

func TestProcessOriginValidation(t *testing.T) {
	tests := []struct {
		name           string
		method         string
		origin         string
		frontendDomain string
		want           string
		wantErr        bool
	}{
		{
			name:           "OPTIONS request skips validation",
			method:         "OPTIONS",
			origin:         "https://evil.com",
			frontendDomain: "balansi.me",
			want:           "https://evil.com",
			wantErr:        false,
		},
		{
			name:           "Valid origin passes validation",
			method:         "POST",
			origin:         "https://balansi.me",
			frontendDomain: "balansi.me",
			want:           "https://balansi.me",
			wantErr:        false,
		},
		{
			name:           "Valid subdomain passes validation",
			method:         "GET",
			origin:         "https://demo.balansi.me",
			frontendDomain: "balansi.me",
			want:           "https://demo.balansi.me",
			wantErr:        false,
		},
		{
			name:           "Invalid origin fails validation",
			method:         "POST",
			origin:         "https://evil.com",
			frontendDomain: "balansi.me",
			want:           "",
			wantErr:        true,
		},
		{
			name:           "Empty frontend domain skips validation",
			method:         "POST",
			origin:         "https://any.com",
			frontendDomain: "",
			want:           "https://any.com",
			wantErr:        false,
		},
		{
			name:           "Empty origin skips validation",
			method:         "POST",
			origin:         "",
			frontendDomain: "balansi.me",
			want:           "",
			wantErr:        false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			req := &mockHTTPRequest{method: tt.method, origin: tt.origin}

			got, err := ProcessOriginValidation(req, tt.frontendDomain)

			if tt.wantErr {
				assert.Error(t, err)
				assert.Equal(t, tt.want, got)
			} else {
				assert.NoError(t, err)
				assert.Equal(t, tt.want, got)
			}
		})
	}
}

func TestProcessCORSOptions(t *testing.T) {
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
			got := ProcessCORSOptions(tt.origin)

			// Check response structure
			assert.Equal(t, 200, got.StatusCode)
			assert.Equal(t, "", got.Body)

			// Check CORS headers are present
			assertCORSHeaders(t, got.Headers)
		})
	}
}
