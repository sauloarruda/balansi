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
