variable "user_pool_name" {
  description = "Name of the Cognito User Pool"
  type        = string
}

variable "project_name" {
  description = "Project name used in resource naming"
  type        = string
  default     = "balansi"
}

variable "environment" {
  description = "Environment name (dev, staging, production)"
  type        = string
}

variable "callback_urls" {
  description = "List of allowed OAuth callback URLs"
  type        = list(string)

  validation {
    condition     = length(var.callback_urls) > 0
    error_message = "At least one callback URL must be provided."
  }
}

variable "logout_urls" {
  description = "List of allowed logout URLs"
  type        = list(string)

  validation {
    condition     = length(var.logout_urls) > 0
    error_message = "At least one logout URL must be provided."
  }
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
