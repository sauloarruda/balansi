package http

import (
	"net/http"

	"github.com/aws/aws-lambda-go/events"
)

// HTTPResponse represents a platform-agnostic HTTP response
type HTTPResponse struct {
	StatusCode int
	Headers    map[string]string
	Body       string
}

// ToLambdaResponse converts HTTPResponse to Lambda API Gateway response
func (r HTTPResponse) ToLambdaResponse() events.APIGatewayV2HTTPResponse {
	return events.APIGatewayV2HTTPResponse{
		StatusCode: r.StatusCode,
		Headers:    r.Headers,
		Body:       r.Body,
	}
}

// WriteTo writes HTTPResponse to http.ResponseWriter (for local server)
func (r HTTPResponse) WriteTo(w http.ResponseWriter) {
	// Set headers
	for key, value := range r.Headers {
		w.Header().Set(key, value)
	}

	// Set status code
	w.WriteHeader(r.StatusCode)

	// Write body
	if r.Body != "" {
		w.Write([]byte(r.Body))
	}
}
