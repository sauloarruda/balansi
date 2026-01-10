output "user_pool_id" {
  description = "Cognito User Pool ID"
  value       = aws_cognito_user_pool.main.id
}

output "client_id" {
  description = "Cognito User Pool Client ID"
  value       = aws_cognito_user_pool_client.main.id
}

output "client_secret" {
  description = "Cognito User Pool Client Secret"
  value       = aws_cognito_user_pool_client.main.client_secret
  sensitive   = true
}

output "domain" {
  description = "Cognito User Pool Domain name (used to construct full URL in Rails)"
  value       = aws_cognito_user_pool_domain.main.domain
}

output "region" {
  description = "AWS Region where Cognito is deployed"
  value       = data.aws_region.current.name
}

output "user_pool_arn" {
  description = "Cognito User Pool ARN"
  value       = aws_cognito_user_pool.main.arn
}
