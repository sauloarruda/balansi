# Cognito User Pool
resource "aws_cognito_user_pool" "main" {
  name = var.user_pool_name

  # Use email as username instead of a separate username field
  username_attributes = ["email"]

  # Password policy
  password_policy {
    minimum_length                   = 8
    require_lowercase                = true
    require_uppercase                = true
    require_numbers                  = true
    require_symbols                  = true
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
  access_token_validity  = 60 # 60 minutes = 1 hour
  id_token_validity      = 60 # 60 minutes = 1 hour
  refresh_token_validity = 30 # 30 days (matches Rails session expiration)

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

  # Supported Identity Providers
  # Required for Managed Login V2 - must include COGNITO to allow users to sign in with email/username
  supported_identity_providers = ["COGNITO"]
}

# Cognito User Pool Domain (default domain)
# Note: Cognito domain names must be globally unique across all AWS accounts.
# The random_id.domain_suffix ensures uniqueness and prevents conflicts.
resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.project_name}-${var.environment}-${random_id.domain_suffix.hex}"
  user_pool_id = aws_cognito_user_pool.main.id

  # Enable Managed Login V2 (newer, updated version with branding support)
  managed_login_version = 2
}

# Random ID for domain suffix (to ensure unique domain names)
resource "random_id" "domain_suffix" {
  byte_length = 4
}

# Automatically configure Managed Login V2 branding after domain is created
# This ensures branding is set up without requiring manual script execution
resource "null_resource" "configure_managed_login_branding" {
  triggers = {
    user_pool_id = aws_cognito_user_pool.main.id
    client_id    = aws_cognito_user_pool_client.main.id
    region       = data.aws_region.current.name
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      
      USER_POOL_ID="${aws_cognito_user_pool.main.id}"
      CLIENT_ID="${aws_cognito_user_pool_client.main.id}"
      REGION="${data.aws_region.current.name}"
      
      echo "Configuring Managed Login V2 branding..."
      echo "User Pool ID: $USER_POOL_ID"
      echo "Client ID: $CLIENT_ID"
      echo "Region: $REGION"
      
      # Check if branding already exists
      if aws cognito-idp describe-managed-login-branding-by-client \
        --user-pool-id "$USER_POOL_ID" \
        --client-id "$CLIENT_ID" \
        --region "$REGION" \
        2>/dev/null >/dev/null; then
        echo "✓ Managed Login V2 branding already exists, skipping creation"
      else
        echo "Creating Managed Login V2 branding with Cognito-provided default values..."
        
        # Try with Cognito-provided values first (simpler and recommended)
        if aws cognito-idp create-managed-login-branding \
          --user-pool-id "$USER_POOL_ID" \
          --client-id "$CLIENT_ID" \
          --use-cognito-provided-values \
          --region "$REGION" \
          2>&1; then
          echo "✓ Managed Login V2 branding created successfully with default values!"
        else
          echo "Warning: Failed to create branding with default values, trying custom settings..."
          
          # Fallback to custom settings if default values fail
          SETTINGS_JSON='{"categories":{"form":{"displayGraphics":false,"instructions":{"enabled":true},"languageSelector":{"enabled":true},"location":{"horizontal":"CENTER","vertical":"CENTER"},"sessionTimerDisplay":"NONE"}},"componentClasses":{"buttons":{"borderRadius":4.0}}}'
          
          if aws cognito-idp create-managed-login-branding \
            --user-pool-id "$USER_POOL_ID" \
            --client-id "$CLIENT_ID" \
            --settings "$SETTINGS_JSON" \
            --region "$REGION" \
            2>&1; then
            echo "✓ Managed Login V2 branding created successfully with custom settings!"
          else
            echo "Error: Failed to configure Managed Login V2 branding via AWS CLI"
            echo "Please configure branding manually via AWS Console:"
            echo "1. Go to https://console.aws.amazon.com/cognito/"
            echo "2. Select your User Pool: $USER_POOL_ID"
            echo "3. Go to App integration > Hosted UI > Managed Login branding"
            echo "4. Configure branding settings or use default branding"
            exit 1
          fi
        fi
      fi
    EOT

    interpreter = ["/bin/bash", "-c"]
  }

  depends_on = [
    aws_cognito_user_pool_domain.main,
    aws_cognito_user_pool_client.main
  ]
}
