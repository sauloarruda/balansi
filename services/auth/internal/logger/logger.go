package logger

import (
	"encoding/json"
	"fmt"
	"log"
	"os"
	"reflect"
	"regexp"
	"strings"
)

var (
	// emailRegex matches valid email addresses (full string match)
	emailRegex = regexp.MustCompile(`^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$`)
	// emailRegexInString matches email addresses within strings (without ^$ anchors)
	emailRegexInString = regexp.MustCompile(`[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}`)
)

type LogLevel int

const (
	LogLevelDebug LogLevel = iota
	LogLevelInfo
	LogLevelWarn
	LogLevelError
)

var currentLevel LogLevel = LogLevelInfo

func init() {
	levelStr := strings.ToLower(os.Getenv("LOG_LEVEL"))
	switch levelStr {
	case "debug":
		currentLevel = LogLevelDebug
	case "info":
		currentLevel = LogLevelInfo
	case "warn", "warning":
		currentLevel = LogLevelWarn
	case "error":
		currentLevel = LogLevelError
	default:
		// Default to info if not set or invalid
		currentLevel = LogLevelInfo
	}
}

// redactLogMessage redacts emails in a formatted log message
func redactLogMessage(format string, v ...interface{}) string {
	message := fmt.Sprintf(format, v...)
	return redactEmailsInString(message)
}

// Debug logs a debug message
func Debug(format string, v ...interface{}) {
	if currentLevel <= LogLevelDebug {
		message := redactLogMessage(format, v...)
		log.Print("[DEBUG] " + message)
	}
}

// Info logs an info message
func Info(format string, v ...interface{}) {
	if currentLevel <= LogLevelInfo {
		message := redactLogMessage(format, v...)
		log.Print("[INFO] " + message)
	}
}

// Warn logs a warning message
func Warn(format string, v ...interface{}) {
	if currentLevel <= LogLevelWarn {
		message := redactLogMessage(format, v...)
		log.Print("[WARN] " + message)
	}
}

// Error logs an error message
func Error(format string, v ...interface{}) {
	if currentLevel <= LogLevelError {
		message := redactLogMessage(format, v...)
		log.Print("[ERROR] " + message)
	}
}

// DebugJSON logs a JSON object in debug mode with sensitive data automatically redacted
func DebugJSON(label string, obj interface{}) {
	if currentLevel <= LogLevelDebug {
		redacted := Redact(obj)
		jsonBytes, err := json.MarshalIndent(redacted, "", "  ")
		if err != nil {
			Debug("%s: failed to marshal JSON: %v", label, err)
			return
		}
		Debug("%s:\n%s", label, string(jsonBytes))
	}
}

// redactEmail redacts an email address in the format: sa**@gm**.com
// Shows first 2 chars + 2 asterisks before @, first 2 chars + 2 asterisks after @, then full domain
func redactEmail(email string) string {
	if email == "" {
		return email
	}

	parts := strings.Split(email, "@")
	if len(parts) != 2 {
		return email // Invalid email format, return as is
	}

	localPart := parts[0]
	domainPart := parts[1]

	// Redact local part: first 2 chars + 2 asterisks
	var redactedLocal string
	if len(localPart) <= 2 {
		redactedLocal = localPart + "**"
	} else {
		redactedLocal = localPart[:2] + "**"
	}

	// Redact domain part: first 2 chars + 2 asterisks + full domain extension
	domainParts := strings.Split(domainPart, ".")
	if len(domainParts) < 2 {
		// No dot found, treat entire domain as one part
		if len(domainPart) <= 2 {
			redactedDomain := domainPart + "**"
			return redactedLocal + "@" + redactedDomain
		}
		redactedDomain := domainPart[:2] + "**"
		return redactedLocal + "@" + redactedDomain
	}

	// Extract domain name (before last dot) and extension (after last dot)
	domainName := strings.Join(domainParts[:len(domainParts)-1], ".")
	extension := "." + domainParts[len(domainParts)-1]

	var redactedDomainName string
	if len(domainName) <= 2 {
		redactedDomainName = domainName + "**"
	} else {
		redactedDomainName = domainName[:2] + "**"
	}

	return redactedLocal + "@" + redactedDomainName + extension
}

// isSensitiveField checks if a field name indicates sensitive data
func isSensitiveField(fieldName string) bool {
	lowerName := strings.ToLower(fieldName)
	sensitiveKeywords := []string{
		"password",
		"secret",
		"token",
		"key",
		"credential",
		"auth",
		"hash",
	}

	for _, keyword := range sensitiveKeywords {
		if strings.Contains(lowerName, keyword) {
			return true
		}
	}
	return false
}

// getStringValue safely extracts a string value from a reflect.Value, handling pointers
func getStringValue(val reflect.Value) (string, bool) {
	if val.Kind() == reflect.Ptr {
		if val.IsNil() {
			return "", false
		}
		val = val.Elem()
	}
	if val.Kind() == reflect.String {
		return val.String(), true
	}
	return "", false
}

// isEmailField checks if a field name indicates it might contain an email
func isEmailField(fieldName string) bool {
	lowerName := strings.ToLower(fieldName)
	return lowerName == "email" || lowerName == "username" || lowerName == "destination"
}

// redactStringValue redacts a string value if it's an email, otherwise returns as is
func redactStringValue(str string) interface{} {
	if emailRegex.MatchString(str) {
		return redactEmail(str)
	}
	return str
}

// redactEmailsInString finds and redacts all email addresses within a string
// This handles cases like Filter: "email = \"user@example.com\""
func redactEmailsInString(str string) string {
	// Find all email matches in the string (using regex without ^$ anchors)
	matches := emailRegexInString.FindAllString(str, -1)
	if len(matches) == 0 {
		return str
	}

	// Replace each email with its redacted version
	result := str
	for _, email := range matches {
		redacted := redactEmail(email)
		result = strings.ReplaceAll(result, email, redacted)
	}
	return result
}

// extractJSONFieldName extracts the JSON field name from a struct field tag
func extractJSONFieldName(field reflect.StructField) string {
	jsonTag := field.Tag.Get("json")
	if jsonTag == "" {
		return field.Name
	}
	jsonParts := strings.Split(jsonTag, ",")
	if jsonParts[0] != "" && jsonParts[0] != "-" {
		return jsonParts[0]
	}
	return field.Name
}

// checkIfEmailAttribute checks if a struct has a Name field with value "email"
func checkIfEmailAttribute(typ reflect.Type, val reflect.Value) bool {
	for i := 0; i < val.NumField(); i++ {
		field := typ.Field(i)
		fieldVal := val.Field(i)
		if !fieldVal.CanInterface() {
			continue
		}
		fieldName := extractJSONFieldName(field)
		if strings.ToLower(fieldName) == "name" {
			if nameStr, ok := getStringValue(fieldVal); ok {
				return strings.ToLower(nameStr) == "email"
			}
		}
	}
	return false
}

// redactMapValue processes a map value based on its key
func redactMapValue(keyStr string, valueVal reflect.Value, value interface{}) interface{} {
	if isSensitiveField(keyStr) {
		return "[REDACTED]"
	}
	if isEmailField(keyStr) {
		if str, ok := getStringValue(valueVal); ok {
			return redactStringValue(str)
		}
	}
	return Redact(value)
}

// redactStructField processes a struct field
func redactStructField(field reflect.StructField, fieldVal reflect.Value, fieldValue interface{}, jsonFieldName string, isEmailAttribute bool) interface{} {
	fieldName := field.Name

	// Check if field is sensitive
	if isSensitiveField(fieldName) || isSensitiveField(jsonFieldName) {
		return "[REDACTED]"
	}

	// Handle email/username fields or Value fields when Name is "email"
	if isEmailField(fieldName) || (strings.ToLower(fieldName) == "value" && isEmailAttribute) {
		if str, ok := getStringValue(fieldVal); ok {
			return redactStringValue(str)
		}
	}

	return Redact(fieldValue)
}

// Redact recursively sanitizes sensitive data from a struct or map
func Redact(obj interface{}) interface{} {
	if obj == nil {
		return nil
	}

	val := reflect.ValueOf(obj)
	typ := reflect.TypeOf(obj)

	// Handle pointers
	if val.Kind() == reflect.Ptr {
		if val.IsNil() {
			return nil
		}
		val = val.Elem()
		typ = typ.Elem()
	}

	// Handle strings - check if it's an email or contains emails
	if val.Kind() == reflect.String {
		str := val.String()
		// If the entire string is an email, redact it
		if emailRegex.MatchString(str) {
			return redactEmail(str)
		}
		// Otherwise, check if it contains emails (like in Filter strings)
		return redactEmailsInString(str)
	}

	// Handle maps
	if val.Kind() == reflect.Map {
		redactedMap := make(map[string]interface{})
		for _, key := range val.MapKeys() {
			keyStr := fmt.Sprintf("%v", key.Interface())
			valueVal := val.MapIndex(key)
			value := valueVal.Interface()
			redactedMap[keyStr] = redactMapValue(keyStr, valueVal, value)
		}
		return redactedMap
	}

	// Handle slices
	if val.Kind() == reflect.Slice {
		redactedSlice := make([]interface{}, val.Len())
		for i := 0; i < val.Len(); i++ {
			redactedSlice[i] = Redact(val.Index(i).Interface())
		}
		return redactedSlice
	}

	// Handle structs
	if val.Kind() == reflect.Struct {
		redactedMap := make(map[string]interface{})
		isEmailAttribute := checkIfEmailAttribute(typ, val)

		for i := 0; i < val.NumField(); i++ {
			field := typ.Field(i)
			fieldVal := val.Field(i)

			// Skip unexported fields
			if !fieldVal.CanInterface() {
				continue
			}

			jsonFieldName := extractJSONFieldName(field)
			fieldValue := fieldVal.Interface()
			redactedValue := redactStructField(field, fieldVal, fieldValue, jsonFieldName, isEmailAttribute)
			redactedMap[jsonFieldName] = redactedValue
		}
		return redactedMap
	}

	// For other types, return as is
	return obj
}
