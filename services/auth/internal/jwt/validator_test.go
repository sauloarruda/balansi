package jwt

import (
	"context"
	"crypto/rand"
	"crypto/rsa"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"services/auth/internal/config"

	"github.com/lestrrat-go/jwx/v2/jwa"
	"github.com/lestrrat-go/jwx/v2/jwk"
	"github.com/lestrrat-go/jwx/v2/jws"
	"github.com/lestrrat-go/jwx/v2/jwt"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestNewValidator(t *testing.T) {
	t.Run("With Custom Endpoint", func(t *testing.T) {
		cfg := &config.Config{
			CognitoEndpoint:   "http://localhost:9229",
			CognitoUserPoolID: "pool-1",
		}
		v := NewValidator(cfg)
		assert.Equal(t, "http://localhost:9229/pool-1/.well-known/jwks.json", v.jwksURL)
		assert.Equal(t, "pool-1", v.userPoolID)
	})

	t.Run("With AWS Region", func(t *testing.T) {
		cfg := &config.Config{
			CognitoEndpoint:   "", // Empty, should use region
			AWSRegion:         "us-west-2",
			CognitoUserPoolID: "us-west-2_12345",
		}
		v := NewValidator(cfg)
		assert.Equal(t, "https://cognito-idp.us-west-2.amazonaws.com/us-west-2_12345/.well-known/jwks.json", v.jwksURL)
	})
}

func TestValidator_ValidateToken(t *testing.T) {
	// Generate RSA key pair
	privateKey, err := rsa.GenerateKey(rand.Reader, 2048)
	require.NoError(t, err)

	// Create JWK from private key to attach Key ID
	key, err := jwk.FromRaw(privateKey)
	require.NoError(t, err)
	err = key.Set(jwk.KeyIDKey, "test-key-id")
	require.NoError(t, err)
	err = key.Set(jwk.AlgorithmKey, jwa.RS256)
	require.NoError(t, err)
	err = key.Set(jwk.KeyUsageKey, "sig")
	require.NoError(t, err)

	// Setup mock JWKS server
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// Create public key JWK
		pubKey, _ := key.PublicKey()

		// Create a skipped key (wrong use)
		skippedKey, _ := jwk.FromRaw(privateKey)
		skippedKey.Set(jwk.KeyIDKey, "skipped-key")
		pubKeySkipped, _ := skippedKey.PublicKey()
		pubKeySkipped.Set(jwk.KeyUsageKey, "enc") // Set explicitly on public key

		// Marshal to JSON
		// Use json.Marshal directly on keys which should respect tags
		buf, _ := json.Marshal(map[string]interface{}{
			"keys": []interface{}{pubKey, pubKeySkipped},
		})
		w.Write(buf)
	}))
	defer server.Close()

	cfg := &config.Config{
		CognitoEndpoint:   server.URL,
		CognitoUserPoolID: "us-east-1_xxxxxxxxx",
	}

	validator := NewValidator(cfg)
	validator.SetJWKSURL(server.URL)
	validator.cacheTTL = 1 * time.Second

	t.Run("Valid Token", func(t *testing.T) {
		tok, err := jwt.NewBuilder().
			Issuer("https://cognito-idp.us-east-1.amazonaws.com/us-east-1_xxxxxxxxx").
			Subject("user-123").
			Expiration(time.Now().Add(1 * time.Hour)).
			JwtID("test-jwt-id").
			Build()
		require.NoError(t, err)

		payload, err := json.Marshal(tok)
		require.NoError(t, err)

		hdrs := jws.NewHeaders()
		hdrs.Set(jws.KeyIDKey, "test-key-id")
		hdrs.Set(jws.TypeKey, "JWT")

		signed, err := jws.Sign(payload, jws.WithKey(jwa.RS256, key, jws.WithProtectedHeaders(hdrs)))
		require.NoError(t, err)

		sub, err := validator.ValidateToken(context.Background(), string(signed))
		assert.NoError(t, err)
		assert.Equal(t, "user-123", sub)
	})

	t.Run("Expired Token", func(t *testing.T) {
		tok, err := jwt.NewBuilder().
			Subject("user-123").
			Expiration(time.Now().Add(-1 * time.Hour)).
			Build()
		require.NoError(t, err)

		payload, err := json.Marshal(tok)
		require.NoError(t, err)

		hdrs := jws.NewHeaders()
		hdrs.Set(jws.KeyIDKey, "test-key-id")
		hdrs.Set(jws.TypeKey, "JWT")

		signed, err := jws.Sign(payload, jws.WithKey(jwa.RS256, key, jws.WithProtectedHeaders(hdrs)))
		require.NoError(t, err)

		_, err = validator.ValidateToken(context.Background(), string(signed))
		assert.Error(t, err)
		assert.Contains(t, err.Error(), "failed to verify token signature")
		assert.Contains(t, err.Error(), "exp")
	})

	t.Run("Invalid Signature", func(t *testing.T) {
		otherKeyRaw, _ := rsa.GenerateKey(rand.Reader, 2048)
		otherKey, _ := jwk.FromRaw(otherKeyRaw)
		otherKey.Set(jwk.KeyIDKey, "test-key-id") // Same ID, different key

		tok, err := jwt.NewBuilder().
			Subject("user-123").
			Expiration(time.Now().Add(1 * time.Hour)).
			Build()
		require.NoError(t, err)

		payload, err := json.Marshal(tok)
		require.NoError(t, err)

		hdrs := jws.NewHeaders()
		hdrs.Set(jws.KeyIDKey, "test-key-id")
		hdrs.Set(jws.TypeKey, "JWT")

		signed, err := jws.Sign(payload, jws.WithKey(jwa.RS256, otherKey, jws.WithProtectedHeaders(hdrs)))
		require.NoError(t, err)

		_, err = validator.ValidateToken(context.Background(), string(signed))
		assert.Error(t, err)
		assert.Contains(t, err.Error(), "failed to verify token signature")
	})

	t.Run("Unknown Key ID", func(t *testing.T) {
		unknownKey, _ := jwk.FromRaw(privateKey)
		unknownKey.Set(jwk.KeyIDKey, "unknown-key")

		tok, err := jwt.NewBuilder().
			Subject("user-123").
			Build()
		require.NoError(t, err)

		payload, err := json.Marshal(tok)
		require.NoError(t, err)

		hdrs := jws.NewHeaders()
		hdrs.Set(jws.KeyIDKey, "unknown-key")
		hdrs.Set(jws.TypeKey, "JWT")

		signed, err := jws.Sign(payload, jws.WithKey(jwa.RS256, unknownKey, jws.WithProtectedHeaders(hdrs)))
		require.NoError(t, err)

		_, err = validator.ValidateToken(context.Background(), string(signed))
		assert.Error(t, err)
		assert.Contains(t, err.Error(), "key with kid unknown-key not found")
	})

	t.Run("Missing Sub Claim", func(t *testing.T) {
		tok, _ := jwt.NewBuilder().
			Issuer("https://cognito-idp.us-east-1.amazonaws.com/us-east-1_xxxxxxxxx").
			Expiration(time.Now().Add(time.Hour)).
			JwtID("test-jwt-id").
			Build() // No Subject

		payload, _ := json.Marshal(tok)
		hdrs := jws.NewHeaders()
		hdrs.Set(jws.KeyIDKey, "test-key-id")
		hdrs.Set(jws.TypeKey, "JWT")
		signed, _ := jws.Sign(payload, jws.WithKey(jwa.RS256, key, jws.WithProtectedHeaders(hdrs)))

		_, err := validator.ValidateToken(context.Background(), string(signed))
		assert.Error(t, err)
		assert.Contains(t, err.Error(), "token missing sub claim")
	})

	/*
		t.Run("Skipped Key (Wrong Usage)", func(t *testing.T) {
			// ...
		})
	*/

	t.Run("Malformed Token", func(t *testing.T) {
		_, err := validator.ValidateToken(context.Background(), "not.a.token")
		assert.Error(t, err)
		assert.Contains(t, err.Error(), "failed to parse JWS")
	})

	t.Run("Missing Kid Header", func(t *testing.T) {
		// Use a key without ID to ensure kid is not automatically added
		rawKey, _ := rsa.GenerateKey(rand.Reader, 2048)
		keyNoId, _ := jwk.FromRaw(rawKey)
		// Do NOT set KeyID
		keyNoId.Set(jwk.AlgorithmKey, jwa.RS256)
		keyNoId.Set(jwk.KeyUsageKey, "sig")

		tok, _ := jwt.NewBuilder().Subject("user").Build()
		payload, _ := json.Marshal(tok)

		signed, _ := jws.Sign(payload, jws.WithKey(jwa.RS256, keyNoId))

		_, err := validator.ValidateToken(context.Background(), string(signed))
		require.Error(t, err)
		assert.Contains(t, err.Error(), "token missing kid header")
	})

	t.Run("Fetch JWKS Error", func(t *testing.T) {
		badCfg := &config.Config{
			CognitoEndpoint: "http://localhost:9999", // Unreachable
		}
		v := NewValidator(badCfg)
		v.SetJWKSURL("http://localhost:9999")

		// Use a token with a kid that requires fetching
		tok, _ := jwt.NewBuilder().Subject("user").Build()
		payload, _ := json.Marshal(tok)
		hdrs := jws.NewHeaders()
		hdrs.Set(jws.KeyIDKey, "new-key")
		signed, _ := jws.Sign(payload, jws.WithKey(jwa.RS256, key, jws.WithProtectedHeaders(hdrs)))

		_, err := v.ValidateToken(context.Background(), string(signed))
		assert.Error(t, err)
		assert.Contains(t, err.Error(), "failed to fetch JWKS")
	})

	t.Run("Refresh on Unknown Key ID", func(t *testing.T) {
		// Create validator with short intervals for testing
		testValidator := NewValidator(cfg)
		testValidator.SetJWKSURL(server.URL)
		testValidator.cacheTTL = 1 * time.Hour // Long TTL
		testValidator.minRefreshInterval = 1 * time.Millisecond // Very short for testing

		// First, validate a known token to populate cache
		tok, err := jwt.NewBuilder().
			Subject("user-123").
			Expiration(time.Now().Add(1 * time.Hour)).
			Build()
		require.NoError(t, err)

		payload, err := json.Marshal(tok)
		require.NoError(t, err)

		hdrs := jws.NewHeaders()
		hdrs.Set(jws.KeyIDKey, "test-key-id")
		hdrs.Set(jws.TypeKey, "JWT")

		signed, err := jws.Sign(payload, jws.WithKey(jwa.RS256, key, jws.WithProtectedHeaders(hdrs)))
		require.NoError(t, err)

		// This should work and populate cache
		sub, err := testValidator.ValidateToken(context.Background(), string(signed))
		assert.NoError(t, err)
		assert.Equal(t, "user-123", sub)

		// Now try with unknown key - should attempt refresh due to short minRefreshInterval
		// (In real scenario, this would succeed if JWKS had the key, but here it will fail)
		unknownKey, _ := jwk.FromRaw(privateKey)
		unknownKey.Set(jwk.KeyIDKey, "unknown-key")

		tok2, err := jwt.NewBuilder().
			Subject("user-456").
			Expiration(time.Now().Add(1 * time.Hour)).
			Build()
		require.NoError(t, err)

		payload2, err := json.Marshal(tok2)
		require.NoError(t, err)

		hdrs2 := jws.NewHeaders()
		hdrs2.Set(jws.KeyIDKey, "unknown-key")
		hdrs2.Set(jws.TypeKey, "JWT")

		signed2, err := jws.Sign(payload2, jws.WithKey(jwa.RS256, unknownKey, jws.WithProtectedHeaders(hdrs2)))
		require.NoError(t, err)

		// This should attempt refresh and then fail (since unknown-key is not in JWKS)
		_, err = testValidator.ValidateToken(context.Background(), string(signed2))
		assert.Error(t, err)
		assert.Contains(t, err.Error(), "key with kid unknown-key not found")
	})
}
