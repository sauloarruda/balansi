package models

// SessionCookieData represents the data stored in the session_id cookie
// This data is encrypted before being stored in the cookie
type SessionCookieData struct {
	RefreshToken string `json:"refreshToken"`
	UserID       int64  `json:"userId"`
	Username     string `json:"username"`
}

// AccessTokenResponse represents the response from /auth/refresh
type AccessTokenResponse struct {
	AccessToken string `json:"accessToken"`
	ExpiresIn   int32  `json:"expiresIn"`
}

// UserInfoResponse represents the response from /auth/me
type UserInfoResponse struct {
	ID   int64  `json:"id"`
	Name string `json:"name"`
}

// ConfirmRequest represents the request payload for email confirmation
type ConfirmRequest struct {
	UserID int64  `json:"userId"`
	Code   string `json:"code"`
}

// TokenResponse represents the complete token response from authentication
type TokenResponse struct {
	AccessToken  string `json:"accessToken"`
	IDToken      string `json:"idToken"`
	RefreshToken string `json:"refreshToken"`
	ExpiresIn    int32  `json:"expiresIn"`
	TokenType    string `json:"tokenType"`
}

// AuthenticationTokenResult represents the result of a successful authentication
// Contains data needed to create session cookie for any authentication flow
type AuthenticationTokenResult struct {
	RefreshToken string `json:"refreshToken"`
	UserID       int64  `json:"userId"`
	Username     string `json:"username"`
}
