package handlers

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
	"services/auth/internal/jwt"
	"services/auth/internal/models"
	"services/auth/internal/testhelpers"

	"github.com/aws/aws-lambda-go/events"
	"github.com/lestrrat-go/jwx/v2/jwa"
	"github.com/lestrrat-go/jwx/v2/jwk"
	"github.com/lestrrat-go/jwx/v2/jws"
	jwxjwt "github.com/lestrrat-go/jwx/v2/jwt"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
)

func TestMeHandler_Handle(t *testing.T) {
	// 1. Setup Mock JWKS
	privateKey, _ := rsa.GenerateKey(rand.Reader, 2048)
	key, _ := jwk.FromRaw(privateKey)
	key.Set(jwk.KeyIDKey, "key-1")
	key.Set(jwk.AlgorithmKey, jwa.RS256)
	key.Set(jwk.KeyUsageKey, "sig")

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		pubKey, _ := key.PublicKey()
		buf, _ := json.Marshal(map[string]interface{}{
			"keys": []interface{}{pubKey},
		})
		w.Write(buf)
	}))
	defer server.Close()

	cfg := &config.Config{
		CognitoEndpoint:   server.URL,
		CognitoUserPoolID: "pool-1",
	}
	validator := jwt.NewValidator(cfg)
	validator.SetJWKSURL(server.URL)

	// Helper to generate token
	generateToken := func(sub string, valid bool) string {
		builder := jwxjwt.NewBuilder().
			Subject(sub).
			Expiration(time.Now().Add(time.Hour))

		if !valid {
			return "invalid-token"
		}

		tok, _ := builder.Build()
		payload, _ := json.Marshal(tok)

		hdrs := jws.NewHeaders()
		hdrs.Set(jws.KeyIDKey, "key-1")
		hdrs.Set(jws.TypeKey, "JWT")

		// Correct nesting: WithProtectedHeaders INSIDE WithKey
		signed, _ := jws.Sign(payload, jws.WithKey(jwa.RS256, key, jws.WithProtectedHeaders(hdrs)))
		return string(signed)
	}

	t.Run("Success", func(t *testing.T) {
		mockRepo := new(testhelpers.MockUserRepository)
		mockCognito := new(testhelpers.MockCognitoClient)
		handler := NewMeHandlerWithInterface(mockRepo, mockCognito, validator)

		validToken := generateToken("cognito-sub-123", true)
		ctx := context.Background()
		req := events.APIGatewayV2HTTPRequest{
			Headers: map[string]string{"Authorization": "Bearer " + validToken},
		}

		expectedUser := &models.User{
			ID:        1,
			Name:      "John Doe",
			CognitoID: awsString("cognito-sub-123"),
		}
		mockRepo.On("FindByCognitoID", ctx, "cognito-sub-123").Return(expectedUser, nil)

		resp, err := handler.Handle(ctx, req)

		require.NoError(t, err)
		assert.Equal(t, 200, resp.StatusCode)

		var body models.UserInfoResponse
		json.Unmarshal([]byte(resp.Body), &body)
		assert.Equal(t, int64(1), body.ID)
		assert.Equal(t, "John Doe", body.Name)
	})

	t.Run("Invalid Token", func(t *testing.T) {
		mockRepo := new(testhelpers.MockUserRepository)
		mockCognito := new(testhelpers.MockCognitoClient)
		handler := NewMeHandlerWithInterface(mockRepo, mockCognito, validator)

		req := events.APIGatewayV2HTTPRequest{
			Headers: map[string]string{"Authorization": "Bearer invalid-token"},
		}
		resp, err := handler.Handle(context.Background(), req)
		require.NoError(t, err)
		assert.Equal(t, 401, resp.StatusCode)
	})

	t.Run("User Not Found", func(t *testing.T) {
		mockRepo := new(testhelpers.MockUserRepository)
		mockCognito := new(testhelpers.MockCognitoClient)
		handler := NewMeHandlerWithInterface(mockRepo, mockCognito, validator)

		// Use a DIFFERENT sub to ensure no mock collision
		validToken := generateToken("cognito-sub-404", true)
		req := events.APIGatewayV2HTTPRequest{
			Headers: map[string]string{"Authorization": "Bearer " + validToken},
		}

		mockRepo.On("FindByCognitoID", mock.Anything, "cognito-sub-404").Return(nil, nil)

		resp, err := handler.Handle(context.Background(), req)
		require.NoError(t, err)
		assert.Equal(t, 404, resp.StatusCode)
	})
}

func awsString(s string) *string { return &s }
