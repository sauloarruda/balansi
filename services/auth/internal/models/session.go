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
