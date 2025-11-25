package http

import (
	"net/url"
	"os"
	"strings"

	"github.com/aws/aws-lambda-go/events"
)

// ExtractBearerToken extracts the token from "Bearer <token>" format
func ExtractBearerToken(authHeader string) string {
	parts := strings.Split(authHeader, " ")
	if len(parts) != 2 || strings.ToLower(parts[0]) != "bearer" {
		return ""
	}
	return parts[1]
}

// ExtractCookieValue extracts a cookie value from the Cookies array (HTTP API v2 format)
// Returns the cookie value or empty string if not found
func ExtractCookieValue(cookies []string, cookieName string) string {
	if len(cookies) == 0 {
		return ""
	}

	for _, cookie := range cookies {
		prefix := cookieName + "="
		if strings.HasPrefix(cookie, prefix) {
			value := strings.TrimPrefix(cookie, prefix)
			// Remove any trailing attributes (e.g., "; HttpOnly")
			if idx := strings.Index(value, ";"); idx != -1 {
				value = value[:idx]
			}
			return strings.TrimSpace(value)
		}
	}

	return ""
}

// BuildCookieHeader builds the Set-Cookie header with appropriate attributes
// Handles both same-domain and cross-domain scenarios
func BuildCookieHeader(cookieValue string, cookieName string, req events.APIGatewayV2HTTPRequest) string {
	cookie := cookieName + "=" + cookieValue + "; Path=/; HttpOnly; Max-Age=2592000"

	// Get origin from request headers
	origin := req.Headers["origin"]
	if origin == "" {
		origin = req.Headers["Origin"]
	}

	isProduction := req.RequestContext.DomainName != "" && req.RequestContext.DomainName != "localhost"

	if isProduction {
		// In production (HTTPS), use SameSite=None with Secure for cross-origin support
		cookie += "; SameSite=None; Secure"

		// Determine cookie domain using environment variables or automatic detection
		cookieDomain := getCookieDomain(origin, req.RequestContext.DomainName)
		if cookieDomain != "" {
			cookie += "; Domain=" + cookieDomain
		}
	} else {
		// In local development (HTTP), use SameSite=Lax (Secure not required)
		cookie += "; SameSite=Lax"
	}

	return cookie
}

// getCookieDomain determines the cookie domain to use
// Priority:
// 1. COOKIE_DOMAIN environment variable (if set, use directly)
// 2. FRONTEND_DOMAIN and API_DOMAIN environment variables (extract shared domain)
// 3. Automatic detection from Origin header and API Gateway domain name (fallback)
func getCookieDomain(origin, apiDomain string) string {
	// Priority 1: Use COOKIE_DOMAIN if explicitly set
	if cookieDomain := os.Getenv("COOKIE_DOMAIN"); cookieDomain != "" {
		// Ensure it starts with a dot if it's a domain base (e.g., ".balansi.me")
		if !strings.HasPrefix(cookieDomain, ".") && strings.Contains(cookieDomain, ".") {
			// Extract base domain and add leading dot
			parts := strings.Split(cookieDomain, ".")
			if len(parts) >= 2 {
				baseDomain := strings.Join(parts[len(parts)-2:], ".")
				return "." + baseDomain
			}
		}
		return cookieDomain
	}

	// Priority 2: Use FRONTEND_DOMAIN and API_DOMAIN if both are set
	frontendDomain := os.Getenv("FRONTEND_DOMAIN")
	envAPIDomain := os.Getenv("API_DOMAIN")
	if frontendDomain != "" && envAPIDomain != "" {
		if domain := extractSharedDomainFromStrings(frontendDomain, envAPIDomain); domain != "" {
			return domain
		}
	}

	// Priority 3: Automatic detection from request (fallback)
	if origin != "" && apiDomain != "" {
		if domain := extractSharedDomain(origin, apiDomain); domain != "" {
			return domain
		}
	}

	return ""
}

// extractSharedDomainFromStrings extracts the shared domain base from two domain strings
// Similar to extractSharedDomain but works with plain domain strings instead of URLs
func extractSharedDomainFromStrings(domain1, domain2 string) string {
	if domain1 == "" || domain2 == "" {
		return ""
	}

	// Remove ports if present
	if idx := strings.Index(domain1, ":"); idx != -1 {
		domain1 = domain1[:idx]
	}
	if idx := strings.Index(domain2, ":"); idx != -1 {
		domain2 = domain2[:idx]
	}

	// If same domain, no need for Domain attribute
	if domain1 == domain2 {
		return ""
	}

	// Extract base domain
	parts1 := strings.Split(domain1, ".")
	parts2 := strings.Split(domain2, ".")

	// Need at least 2 parts for a domain (e.g., "example.com")
	if len(parts1) < 2 || len(parts2) < 2 {
		return ""
	}

	// Check if they share the same base domain (last 2 parts: TLD + domain)
	// For domains like "bal-7.demo.balansi.me" and "api.demo.balansi.me"
	// We need to extract "balansi.me" (last 2 parts)
	base1 := strings.Join(parts1[len(parts1)-2:], ".")
	base2 := strings.Join(parts2[len(parts2)-2:], ".")

	if base1 == base2 {
		// Return with leading dot for subdomain sharing
		return "." + base1
	}

	return ""
}

// extractSharedDomain extracts the shared domain base if origin and API domain are subdomains of the same base
// Returns empty string if they're the same domain or not sharing a common base domain
// Example: origin="https://demo.balansi.me", apiDomain="api-demo.balansi.me" -> returns ".balansi.me"
func extractSharedDomain(origin, apiDomain string) string {
	if origin == "" || apiDomain == "" {
		return ""
	}

	// Parse origin URL
	originURL, err := url.Parse(origin)
	if err != nil {
		return ""
	}

	originHost := originURL.Host
	// Remove port if present
	if idx := strings.Index(originHost, ":"); idx != -1 {
		originHost = originHost[:idx]
	}

	// Remove port from API domain if present
	apiHost := apiDomain
	if idx := strings.Index(apiHost, ":"); idx != -1 {
		apiHost = apiHost[:idx]
	}

	// If same domain, no need for Domain attribute
	if originHost == apiHost {
		return ""
	}

	// Extract base domain (e.g., "demo.balansi.me" and "api-demo.balansi.me" -> ".balansi.me")
	// Split by dots and check if they share a common suffix
	originParts := strings.Split(originHost, ".")
	apiParts := strings.Split(apiHost, ".")

	// Need at least 2 parts for a domain (e.g., "example.com")
	if len(originParts) < 2 || len(apiParts) < 2 {
		return ""
	}

	// Check if they share the same base domain (last 2 parts: TLD + domain)
	// Example: "bal-7.demo.balansi.me" -> ["bal-7", "demo", "balansi", "me"] -> base: "balansi.me"
	//          "api.demo.balansi.me" -> ["api", "demo", "balansi", "me"] -> base: "balansi.me"
	//          Shared base: ".balansi.me"
	// For domains with more than 2 parts, we always use the last 2 parts (TLD + domain)
	originBase := strings.Join(originParts[len(originParts)-2:], ".")
	apiBase := strings.Join(apiParts[len(apiParts)-2:], ".")

	if originBase == apiBase {
		// Return with leading dot for subdomain sharing
		return "." + originBase
	}

	return ""
}
