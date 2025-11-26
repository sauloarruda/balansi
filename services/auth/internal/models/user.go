package models

import "time"

type UserStatus string

const (
	UserStatusPendingConfirmation UserStatus = "pending_confirmation"
	UserStatusConfirmed           UserStatus = "confirmed"
)

type User struct {
	ID                int64      `db:"id"`
	Name              string     `db:"name"`
	Email             string     `db:"email"`
	TemporaryPassword *string    `db:"temporary_password"`
	CognitoID         *string    `db:"cognito_id"`
	Status            UserStatus `db:"status"`
	CreatedAt         time.Time  `db:"created_at"`
	UpdatedAt         time.Time  `db:"updated_at"`
}

type SignupRequest struct {
	Name  string `json:"name"`
	Email string `json:"email"`
}

type SignupStatus string

const (
	SignupStatusCreated             SignupStatus = "created"
	SignupStatusPendingConfirmation SignupStatus = "pending_confirmation"
)

type SignupOutcome struct {
	User   *User        `json:"user"`
	Status SignupStatus `json:"status"`
}

type SignupResponse struct {
	ID     int64        `json:"id"`
	Name   string       `json:"name"`
	Email  string       `json:"email"`
	Status SignupStatus `json:"status"`
}

type ForgotPasswordResult struct {
	Destination    string `json:"destination"`
	DeliveryMedium string `json:"deliveryMedium"`
}

type ErrorResponse struct {
	Code    string `json:"code"`
	Message string `json:"message"`
}
