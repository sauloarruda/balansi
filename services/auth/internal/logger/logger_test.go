package logger

import (
	"reflect"
	"testing"
)

func TestRedactEmail(t *testing.T) {
	tests := []struct {
		name     string
		input    string
		expected string
	}{
		{
			name:     "standard email",
			input:    "sauloarruda@gmail.com",
			expected: "sa**@gm**.com",
		},
		{
			name:     "short local part",
			input:    "ab@gmail.com",
			expected: "ab**@gm**.com",
		},
		{
			name:     "single char local part",
			input:    "a@gmail.com",
			expected: "a**@gm**.com",
		},
		{
			name:     "short domain",
			input:    "test@ab.com",
			expected: "te**@ab**.com",
		},
		{
			name:     "subdomain",
			input:    "user@mail.example.com",
			expected: "us**@ma**.com",
		},
		{
			name:     "email with plus",
			input:    "user+tag@example.com",
			expected: "us**@ex**.com",
		},
		{
			name:     "empty email",
			input:    "",
			expected: "",
		},
		{
			name:     "invalid email format",
			input:    "notanemail",
			expected: "notanemail",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := redactEmail(tt.input)
			if result != tt.expected {
				t.Errorf("redactEmail(%q) = %q, want %q", tt.input, result, tt.expected)
			}
		})
	}
}

func TestIsSensitiveField(t *testing.T) {
	tests := []struct {
		name     string
		input    string
		expected bool
	}{
		{"password", "password", true},
		{"Password", "Password", true},
		{"PASSWORD", "PASSWORD", true},
		{"userPassword", "userPassword", true},
		{"secret", "secret", true},
		{"SecretHash", "SecretHash", true},
		{"token", "token", true},
		{"accessToken", "accessToken", true},
		{"apiKey", "apiKey", true},
		{"credential", "credential", true},
		{"auth", "auth", true},
		{"hash", "hash", true},
		{"email", "email", false},
		{"username", "username", false},
		{"name", "name", false},
		{"normalField", "normalField", false},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := isSensitiveField(tt.input)
			if result != tt.expected {
				t.Errorf("isSensitiveField(%q) = %v, want %v", tt.input, result, tt.expected)
			}
		})
	}
}

func TestGetStringValue(t *testing.T) {
	str := "test"
	strPtr := &str
	var nilPtr *string

	tests := []struct {
		name     string
		input    reflect.Value
		expected string
		ok       bool
	}{
		{
			name:     "string value",
			input:    reflect.ValueOf(str),
			expected: "test",
			ok:       true,
		},
		{
			name:     "string pointer",
			input:    reflect.ValueOf(strPtr),
			expected: "test",
			ok:       true,
		},
		{
			name:     "nil pointer",
			input:    reflect.ValueOf(nilPtr),
			expected: "",
			ok:       false,
		},
		{
			name:     "int value",
			input:    reflect.ValueOf(42),
			expected: "",
			ok:       false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result, ok := getStringValue(tt.input)
			if ok != tt.ok {
				t.Errorf("getStringValue() ok = %v, want %v", ok, tt.ok)
			}
			if result != tt.expected {
				t.Errorf("getStringValue() = %q, want %q", result, tt.expected)
			}
		})
	}
}

func TestRedact_String(t *testing.T) {
	tests := []struct {
		name     string
		input    interface{}
		expected interface{}
	}{
		{
			name:     "email string",
			input:    "user@example.com",
			expected: "us**@ex**.com",
		},
		{
			name:     "non-email string",
			input:    "just a string",
			expected: "just a string",
		},
		{
			name:     "string with email in filter",
			input:    "email = \"user@example.com\"",
			expected: "email = \"us**@ex**.com\"",
		},
		{
			name:     "string with multiple emails",
			input:    "user1@example.com and user2@test.com",
			expected: "us**@ex**.com and us**@te**.com",
		},
		{
			name:     "nil",
			input:    nil,
			expected: nil,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := Redact(tt.input)
			if !reflect.DeepEqual(result, tt.expected) {
				t.Errorf("Redact(%v) = %v, want %v", tt.input, result, tt.expected)
			}
		})
	}
}

func TestRedact_Map(t *testing.T) {
	tests := []struct {
		name     string
		input    map[string]interface{}
		expected map[string]interface{}
	}{
		{
			name: "map with password",
			input: map[string]interface{}{
				"username": "user",
				"password": "secret123",
			},
			expected: map[string]interface{}{
				"username": "user",
				"password": "[REDACTED]",
			},
		},
		{
			name: "map with email",
			input: map[string]interface{}{
				"email": "user@example.com",
				"name":  "John",
			},
			expected: map[string]interface{}{
				"email": "us**@ex**.com",
				"name":  "John",
			},
		},
		{
			name: "map with token",
			input: map[string]interface{}{
				"token": "abc123",
				"data":  "some data",
			},
			expected: map[string]interface{}{
				"token": "[REDACTED]",
				"data":  "some data",
			},
		},
		{
			name: "map with email pointer",
			input: map[string]interface{}{
				"email": stringPtr("user@example.com"),
			},
			expected: map[string]interface{}{
				"email": "us**@ex**.com",
			},
		},
		{
			name: "map with Filter containing email",
			input: map[string]interface{}{
				"Filter": "email = \"user@example.com\"",
				"Limit":  1,
			},
			expected: map[string]interface{}{
				"Filter": "email = \"us**@ex**.com\"",
				"Limit":  1,
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := Redact(tt.input)
			resultMap, ok := result.(map[string]interface{})
			if !ok {
				t.Fatalf("Redact() returned %T, want map[string]interface{}", result)
			}
			if !reflect.DeepEqual(resultMap, tt.expected) {
				t.Errorf("Redact() = %v, want %v", resultMap, tt.expected)
			}
		})
	}
}

func TestRedact_Slice(t *testing.T) {
	input := []interface{}{
		"user1@example.com",
		"user2@example.com",
		"notanemail",
	}
	expected := []interface{}{
		"us**@ex**.com",
		"us**@ex**.com",
		"notanemail",
	}

	result := Redact(input)
	resultSlice, ok := result.([]interface{})
	if !ok {
		t.Fatalf("Redact() returned %T, want []interface{}", result)
	}
	if !reflect.DeepEqual(resultSlice, expected) {
		t.Errorf("Redact() = %v, want %v", resultSlice, expected)
	}
}

func TestRedact_Struct(t *testing.T) {
	type TestStruct struct {
		Username string `json:"username"`
		Password string `json:"password"`
		Email    string `json:"email"`
		Name     string `json:"name"`
	}

	input := TestStruct{
		Username: "testuser",
		Password: "secret123",
		Email:    "user@example.com",
		Name:     "Test User",
	}

	result := Redact(input)
	resultMap, ok := result.(map[string]interface{})
	if !ok {
		t.Fatalf("Redact() returned %T, want map[string]interface{}", result)
	}

	if resultMap["password"] != "[REDACTED]" {
		t.Errorf("password = %v, want [REDACTED]", resultMap["password"])
	}
	if resultMap["email"] != "us**@ex**.com" {
		t.Errorf("email = %v, want us**@ex**.com", resultMap["email"])
	}
	if resultMap["username"] != "testuser" {
		t.Errorf("username = %v, want testuser", resultMap["username"])
	}
	if resultMap["name"] != "Test User" {
		t.Errorf("name = %v, want Test User", resultMap["name"])
	}
}

func TestRedact_StructWithPointers(t *testing.T) {
	type TestStruct struct {
		Email    *string `json:"email"`
		Password *string `json:"password"`
		Name     string  `json:"name"`
	}

	email := "user@example.com"
	password := "secret123"
	input := TestStruct{
		Email:    &email,
		Password: &password,
		Name:     "Test",
	}

	result := Redact(input)
	resultMap, ok := result.(map[string]interface{})
	if !ok {
		t.Fatalf("Redact() returned %T, want map[string]interface{}", result)
	}

	if resultMap["password"] != "[REDACTED]" {
		t.Errorf("password = %v, want [REDACTED]", resultMap["password"])
	}
	if resultMap["email"] != "us**@ex**.com" {
		t.Errorf("email = %v, want us**@ex**.com", resultMap["email"])
	}
}

func TestRedact_AttributeType(t *testing.T) {
	type AttributeType struct {
		Name  *string `json:"Name"`
		Value *string `json:"Value"`
	}

	name := "email"
	value := "user@example.com"
	input := AttributeType{
		Name:  &name,
		Value: &value,
	}

	result := Redact(input)
	resultMap, ok := result.(map[string]interface{})
	if !ok {
		t.Fatalf("Redact() returned %T, want map[string]interface{}", result)
	}

	if resultMap["Value"] != "us**@ex**.com" {
		t.Errorf("Value = %v, want us**@ex**.com", resultMap["Value"])
	}
}

func TestRedact_Pointer(t *testing.T) {
	str := "user@example.com"
	input := &str

	result := Redact(input)
	expected := "us**@ex**.com"
	if result != expected {
		t.Errorf("Redact() = %v, want %v", result, expected)
	}
}

func TestDebugJSON(t *testing.T) {
	// Set log level to debug
	originalLevel := currentLevel
	currentLevel = LogLevelDebug
	defer func() { currentLevel = originalLevel }()

	// Test that DebugJSON doesn't panic and redacts correctly
	// We verify the redaction by checking the Redact function directly
	input := map[string]interface{}{
		"password": "secret123",
		"email":    "user@example.com",
	}

	// This should not panic
	DebugJSON("Test", input)

	// Verify redaction works correctly
	redacted := Redact(input)
	redactedMap := redacted.(map[string]interface{})
	if redactedMap["password"] != "[REDACTED]" {
		t.Error("password should be redacted")
	}
	if redactedMap["email"] != "us**@ex**.com" {
		t.Error("email should be redacted")
	}
}

func TestDebugJSON_NotDebugLevel(t *testing.T) {
	// Set log level to info
	originalLevel := currentLevel
	currentLevel = LogLevelInfo
	defer func() { currentLevel = originalLevel }()

	// This should not log anything
	DebugJSON("Test", map[string]interface{}{"test": "value"})
	// If we get here without error, it's working
}

func TestExtractJSONFieldName(t *testing.T) {
	type TestStruct struct {
		Field1   string `json:"field1"`
		Field2   string `json:"field2,omitempty"`
		Field3   string `json:"-"`
		Field4   string `json:""`
		NoTag    string
		EmptyTag string `json:""`
	}

	typ := reflect.TypeOf(TestStruct{})
	tests := []struct {
		name     string
		field    reflect.StructField
		expected string
	}{
		{
			name:     "simple json tag",
			field:    typ.Field(0),
			expected: "field1",
		},
		{
			name:     "json tag with omitempty",
			field:    typ.Field(1),
			expected: "field2",
		},
		{
			name:     "json tag with dash",
			field:    typ.Field(2),
			expected: "Field3",
		},
		{
			name:     "no json tag",
			field:    typ.Field(4),
			expected: "NoTag",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := extractJSONFieldName(tt.field)
			if result != tt.expected {
				t.Errorf("extractJSONFieldName() = %q, want %q", result, tt.expected)
			}
		})
	}
}

func TestIsEmailField(t *testing.T) {
	tests := []struct {
		name     string
		input    string
		expected bool
	}{
		{"email", "email", true},
		{"Email", "Email", true},
		{"EMAIL", "EMAIL", true},
		{"username", "username", true},
		{"Username", "Username", true},
		{"destination", "destination", true},
		{"Destination", "Destination", true},
		{"name", "name", false},
		{"value", "value", false},
		{"other", "other", false},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := isEmailField(tt.input)
			if result != tt.expected {
				t.Errorf("isEmailField(%q) = %v, want %v", tt.input, result, tt.expected)
			}
		})
	}
}

func TestRedact_ComplexNested(t *testing.T) {
	type Nested struct {
		Email    string `json:"email"`
		Password string `json:"password"`
	}

	type Complex struct {
		User      Nested                `json:"user"`
		Tokens    map[string]interface{} `json:"tokens"`
		Users     []Nested              `json:"users"`
		SecretKey string                `json:"secretKey"`
	}

	input := Complex{
		User: Nested{
			Email:    "user@example.com",
			Password: "secret123",
		},
		Tokens: map[string]interface{}{
			"accessToken": "token123",
			"email":       "admin@example.com",
		},
		Users: []Nested{
			{Email: "user1@example.com", Password: "pass1"},
			{Email: "user2@example.com", Password: "pass2"},
		},
		SecretKey: "key123",
	}

	result := Redact(input)
	resultMap, ok := result.(map[string]interface{})
	if !ok {
		t.Fatalf("Redact() returned %T, want map[string]interface{}", result)
	}

	// Verify nested struct
	userMap, ok := resultMap["user"].(map[string]interface{})
	if !ok {
		t.Fatalf("user should be a map, got %T", resultMap["user"])
	}
	if userMap["password"] != "[REDACTED]" {
		t.Error("nested password should be redacted")
	}
	if userMap["email"] != "us**@ex**.com" {
		t.Error("nested email should be redacted")
	}

	// Verify map - "Tokens" field name contains "token" so it should be redacted
	tokensValue := resultMap["tokens"]
	if tokensValue != "[REDACTED]" {
		t.Errorf("tokens should be [REDACTED] because field name contains 'token', got %v", tokensValue)
	}

	// Verify slice
	usersSlice, ok := resultMap["users"].([]interface{})
	if !ok {
		t.Fatalf("users should be a slice, got %T", resultMap["users"])
	}
	if len(usersSlice) == 0 {
		t.Fatal("users slice should not be empty")
	}
	user1Map, ok := usersSlice[0].(map[string]interface{})
	if !ok {
		t.Fatalf("user1 should be a map, got %T", usersSlice[0])
	}
	if user1Map["password"] != "[REDACTED]" {
		t.Error("slice password should be redacted")
	}

	// Verify top-level sensitive field
	if resultMap["secretKey"] != "[REDACTED]" {
		t.Error("secretKey should be redacted")
	}
}

// Helper function
func stringPtr(s string) *string {
	return &s
}

func TestDebugJSON_MarshalError(t *testing.T) {
	// Set log level to debug
	originalLevel := currentLevel
	currentLevel = LogLevelDebug
	defer func() { currentLevel = originalLevel }()

	// Create an object that can't be marshaled (circular reference would be ideal, but hard to create)
	// Instead, we'll test with a channel which can't be marshaled
	ch := make(chan int)

	// This should not panic
	DebugJSON("Test", ch)
}
