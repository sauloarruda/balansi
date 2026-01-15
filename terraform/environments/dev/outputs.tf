output "cognito_user_pool_id" {
  description = "Cognito User Pool ID"
  value       = module.cognito.user_pool_id
}

output "cognito_client_id" {
  description = "Cognito User Pool Client ID"
  value       = module.cognito.client_id
}

output "cognito_client_secret" {
  description = "Cognito User Pool Client Secret"
  value       = module.cognito.client_secret
  sensitive   = true
}

output "cognito_domain" {
  description = "Cognito User Pool Domain"
  value       = module.cognito.domain
}

output "cognito_region" {
  description = "AWS Region where Cognito is deployed"
  value       = module.cognito.region
}
