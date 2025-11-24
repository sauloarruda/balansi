package errors

import "fmt"

// ArgumentError represents an error when an invalid argument is provided.
// Similar to ArgumentError in Rails, it can be checked using errors.Is() or errors.As().
//
// Example usage:
//   if username == "" {
//       return errors.NewArgumentError("username", "cannot be empty")
//   }
//
// In handlers, you can check for it:
//   var argErr *errors.ArgumentError
//   if errors.As(err, &argErr) {
//       // Handle argument error (return 400 Bad Request)
//   }
type ArgumentError struct {
	Argument string
	Message  string
}

func (e *ArgumentError) Error() string {
	if e.Argument != "" {
		return fmt.Sprintf("invalid argument '%s': %s", e.Argument, e.Message)
	}
	return e.Message
}

// NewArgumentError creates a new ArgumentError.
func NewArgumentError(argument, message string) *ArgumentError {
	return &ArgumentError{
		Argument: argument,
		Message:  message,
	}
}
