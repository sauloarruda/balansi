package jwt

import (
	"context"
	"crypto/rsa"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"math/big"
	"net/http"
	"sync"
	"time"

	"services/auth/internal/config"
	"services/auth/internal/logger"

	"github.com/lestrrat-go/jwx/v2/jwa"
	"github.com/lestrrat-go/jwx/v2/jws"
	"github.com/lestrrat-go/jwx/v2/jwt"
)

// Validator validates JWT tokens using Cognito's JWKS endpoint
type Validator struct {
	userPoolID         string
	jwksURL            string
	keys               map[string]*rsa.PublicKey
	keysMutex          sync.RWMutex
	lastFetch          time.Time
	cacheTTL           time.Duration
	minRefreshInterval time.Duration // Minimum time between JWKS fetches to prevent abuse
}

// NewValidator creates a new JWT validator for Cognito tokens
func NewValidator(cfg *config.Config) *Validator {
	// Construct JWKS URL from User Pool ID
	var jwksURL string
	if cfg.CognitoEndpoint == "" {
		// AWS Cognito - use region from config
		jwksURL = fmt.Sprintf("https://cognito-idp.%s.amazonaws.com/%s/.well-known/jwks.json", cfg.AWSRegion, cfg.CognitoUserPoolID)
	} else {
		// Local development - append UserPoolID if endpoint is just the host
		jwksURL = fmt.Sprintf("%s/%s/.well-known/jwks.json", cfg.CognitoEndpoint, cfg.CognitoUserPoolID)
	}

	return &Validator{
		userPoolID:         cfg.CognitoUserPoolID,
		jwksURL:            jwksURL,
		keys:               make(map[string]*rsa.PublicKey),
		cacheTTL:           24 * time.Hour,   // Cache keys for 24 hours
		minRefreshInterval: 30 * time.Second, // Minimum 30 seconds between fetches to prevent abuse
	}
}

// ValidateToken validates a JWT token and returns the user sub (Cognito ID)
func (v *Validator) ValidateToken(ctx context.Context, tokenString string) (string, error) {
	// Parse JWS to get the header and kid
	msg, err := jws.Parse([]byte(tokenString))
	if err != nil {
		return "", fmt.Errorf("failed to parse JWS: %w", err)
	}

	if len(msg.Signatures()) == 0 {
		return "", errors.New("token has no signatures")
	}

	// Extract kid from the first signature's protected header
	kid := msg.Signatures()[0].ProtectedHeaders().KeyID()
	if kid == "" {
		return "", errors.New("token missing kid header")
	}

	// Get public key for this kid
	publicKey, err := v.getPublicKey(ctx, kid)
	if err != nil {
		return "", fmt.Errorf("failed to get public key: %w", err)
	}

	// Verify token signature using the key
	verifiedToken, err := jwt.Parse([]byte(tokenString), jwt.WithKey(jwa.RS256, publicKey))
	if err != nil {
		return "", fmt.Errorf("failed to verify token signature: %w", err)
	}

	// Verify token is not expired
	if err := jwt.Validate(verifiedToken); err != nil {
		return "", fmt.Errorf("token validation failed: %w", err)
	}

	// Extract sub claim
	sub, ok := verifiedToken.Get("sub")
	if !ok {
		return "", errors.New("token missing sub claim")
	}

	subStr, ok := sub.(string)
	if !ok || subStr == "" {
		return "", errors.New("invalid sub claim")
	}

	return subStr, nil
}

// getPublicKey fetches and caches the public key for the given kid
func (v *Validator) getPublicKey(ctx context.Context, kid string) (*rsa.PublicKey, error) {
	// Check cache first
	v.keysMutex.RLock()
	if key, ok := v.keys[kid]; ok {
		v.keysMutex.RUnlock()
		return key, nil
	}
	v.keysMutex.RUnlock()

	// Check if we need to refresh the keys
	v.keysMutex.Lock()
	defer v.keysMutex.Unlock()

	// Double-check after acquiring write lock
	if key, ok := v.keys[kid]; ok {
		return key, nil
	}

	// Fetch fresh keys if cache is stale OR if we have an unknown kid and enough time has passed
	// This handles key rotation while preventing abuse
	timeSinceLastFetch := time.Since(v.lastFetch)
	shouldFetch := timeSinceLastFetch > v.cacheTTL || (len(v.keys) > 0 && timeSinceLastFetch >= v.minRefreshInterval)

	if shouldFetch {
		if err := v.fetchKeys(ctx); err != nil {
			return nil, fmt.Errorf("failed to fetch JWKS: %w", err)
		}
	}

	// Get key from cache after potential refresh
	key, ok := v.keys[kid]
	if !ok {
		return nil, fmt.Errorf("key with kid %s not found in JWKS", kid)
	}

	return key, nil
}

// fetchKeys fetches the JWKS from Cognito and caches the public keys
func (v *Validator) fetchKeys(ctx context.Context) error {
	logger.Info("Fetching JWKS from %s", v.jwksURL)

	req, err := http.NewRequestWithContext(ctx, "GET", v.jwksURL, nil)
	if err != nil {
		return fmt.Errorf("failed to create request: %w", err)
	}

	client := &http.Client{Timeout: 10 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return fmt.Errorf("failed to fetch JWKS: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("JWKS endpoint returned status %d", resp.StatusCode)
	}

	var jwks struct {
		Keys []struct {
			Kid string `json:"kid"`
			Kty string `json:"kty"`
			Use string `json:"use"`
			N   string `json:"n"`
			E   string `json:"e"`
		} `json:"keys"`
	}

	if err := json.NewDecoder(resp.Body).Decode(&jwks); err != nil {
		return fmt.Errorf("failed to decode JWKS: %w", err)
	}

	// Parse and cache keys
	newKeys := make(map[string]*rsa.PublicKey)
	for _, key := range jwks.Keys {
		if key.Kty != "RSA" || key.Use != "sig" {
			continue
		}

		// Decode base64url-encoded modulus and exponent
		nBytes, err := base64.RawURLEncoding.DecodeString(key.N)
		if err != nil {
			logger.Error("Failed to decode modulus for kid %s: %v", key.Kid, err)
			continue
		}

		eBytes, err := base64.RawURLEncoding.DecodeString(key.E)
		if err != nil {
			logger.Error("Failed to decode exponent for kid %s: %v", key.Kid, err)
			continue
		}

		// Convert exponent bytes to int
		var eInt int
		for _, b := range eBytes {
			eInt = eInt<<8 | int(b)
		}

		// Create RSA public key
		publicKey := &rsa.PublicKey{
			N: new(big.Int).SetBytes(nBytes),
			E: eInt,
		}

		newKeys[key.Kid] = publicKey
	}

	// Update cache
	v.keys = newKeys
	v.lastFetch = time.Now()

	logger.Info("Successfully cached %d keys from JWKS", len(newKeys))
	return nil
}

// SetJWKSURL sets the JWKS URL directly (useful for testing)
func (v *Validator) SetJWKSURL(url string) {
	v.jwksURL = url
}
