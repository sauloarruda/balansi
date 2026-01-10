# Cognito User Pool
resource "aws_cognito_user_pool" "main" {
  name = var.user_pool_name

  # Password policy
  password_policy {
    minimum_length    = 8
    require_lowercase = true
    require_uppercase = true
    require_numbers   = true
    require_symbols   = true
    temporary_password_validity_days = 7
  }

  # Schema attributes
  schema {
    name                = "name"
    attribute_data_type = "String"
    required            = true
    mutable             = true
  }

  schema {
    name                = "email"
    attribute_data_type = "String"
    required            = true
    mutable             = true
  }

  # Auto verify email
  auto_verified_attributes = ["email"]

  # Email configuration
  email_configuration {
    email_sending_account = "COGNITO_DEFAULT"
  }

  # Tags are inherited from provider default_tags
  # Module tags can override or add additional tags if needed
  tags = var.tags
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "main" {
  name         = "${var.project_name}-${var.environment}-client"
  user_pool_id = aws_cognito_user_pool.main.id

  # OAuth settings
  generate_secret = true

  # Allowed OAuth flows
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_flows_user_pool_client = true

  # Allowed OAuth scopes
  allowed_oauth_scopes = ["openid", "email", "profile"]

  # Callback URLs
  callback_urls = var.callback_urls

  # Sign-out URLs
  logout_urls = var.logout_urls

  # Token validity (matching Rails session expiration)
  # Values are in minutes, hours, and days as specified in token_validity_units
  access_token_validity  = 60      # 60 minutes = 1 hour
  id_token_validity      = 60      # 60 minutes = 1 hour
  refresh_token_validity = 30      # 30 days (matches Rails session expiration)

  # Token validity units (specify time units for token validity values)
  token_validity_units {
    access_token  = "minutes"
    id_token      = "minutes"
    refresh_token = "days"
  }

  # Prevent user existence errors (security)
  prevent_user_existence_errors = "ENABLED"

  # Explicit auth flows
  # Only ALLOW_REFRESH_TOKEN_AUTH is needed for Hosted UI (used for token refresh)
  # ALLOW_USER_PASSWORD_AUTH and ALLOW_USER_SRP_AUTH are for direct API calls, not needed for Hosted UI
  explicit_auth_flows = [
    "ALLOW_REFRESH_TOKEN_AUTH"
  ]
}

# Cognito User Pool Domain (default domain)
# Note: Cognito domain names must be globally unique across all AWS accounts.
# The random_id.domain_suffix ensures uniqueness and prevents conflicts.
resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.project_name}-${var.environment}-${random_id.domain_suffix.hex}"
  user_pool_id = aws_cognito_user_pool.main.id
}

# Random ID for domain suffix (to ensure unique domain names)
resource "random_id" "domain_suffix" {
  byte_length = 4
}
