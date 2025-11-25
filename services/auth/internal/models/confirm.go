package models

type ConfirmRequest struct {
	UserID int64  `json:"userId"`
	Code   string `json:"code"`
}

type TokenResponse struct {
	AccessToken  string `json:"accessToken"`
	IDToken      string `json:"idToken"`
	RefreshToken string `json:"refreshToken"`
	ExpiresIn    int32  `json:"expiresIn"`
	TokenType    string `json:"tokenType"`
}

// ConfirmResult represents the result of a successful confirmation
// Contains data needed to create session cookie
type ConfirmResult struct {
	RefreshToken string `json:"refreshToken"`
	UserID       int64  `json:"userId"`
	Username     string `json:"username"`
}
