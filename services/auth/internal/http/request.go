package http

import (
	"bytes"
	"io"
	"net/http"
	"strings"

	"github.com/aws/aws-lambda-go/events"
)

// HTTPRequest represents a platform-agnostic HTTP request
type HTTPRequest interface {
	GetMethod() string
	GetPath() string
	GetHeaders() map[string]string
	GetBody() string
	GetOrigin() string
}

// LambdaRequestAdapter adapts API Gateway v2 requests to HTTPRequest interface
type LambdaRequestAdapter struct {
	req events.APIGatewayV2HTTPRequest
}

func NewLambdaRequestAdapter(req events.APIGatewayV2HTTPRequest) *LambdaRequestAdapter {
	return &LambdaRequestAdapter{req: req}
}

func (a *LambdaRequestAdapter) GetMethod() string {
	return a.req.RequestContext.HTTP.Method
}

func (a *LambdaRequestAdapter) GetPath() string {
	return ExtractRequestPath(a.req, "") // Use empty string as default
}

func (a *LambdaRequestAdapter) GetHeaders() map[string]string {
	return a.req.Headers
}

func (a *LambdaRequestAdapter) GetBody() string {
	return a.req.Body
}

func (a *LambdaRequestAdapter) GetOrigin() string {
	return ExtractOrigin(a.req)
}

// LocalRequestAdapter adapts standard http.Request to HTTPRequest interface
type LocalRequestAdapter struct {
	req    *http.Request
	body   string
	origin string
}

func NewLocalRequestAdapter(req *http.Request) *LocalRequestAdapter {
	// Read request body
	body := ""
	if req.Body != nil {
		bodyBytes, _ := io.ReadAll(req.Body)
		body = string(bodyBytes)
		req.Body = io.NopCloser(bytes.NewBuffer(bodyBytes)) // Reset body for potential reuse
	}

	// Extract origin (similar logic to startLocalServer)
	origin := req.Header.Get("Origin")
	if origin == "" {
		// Fallback: try to get from Referer header or use default dev server URL
		referer := req.Header.Get("Referer")
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

	return &LocalRequestAdapter{
		req:    req,
		body:   body,
		origin: origin,
	}
}

func (a *LocalRequestAdapter) GetMethod() string {
	return a.req.Method
}

func (a *LocalRequestAdapter) GetPath() string {
	return a.req.URL.Path
}

func (a *LocalRequestAdapter) GetHeaders() map[string]string {
	headers := make(map[string]string)
	for key, values := range a.req.Header {
		if len(values) > 0 {
			headers[key] = values[0]
		}
	}
	return headers
}

func (a *LocalRequestAdapter) GetBody() string {
	return a.body
}

func (a *LocalRequestAdapter) GetOrigin() string {
	return a.origin
}
