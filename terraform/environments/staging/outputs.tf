output "ec2_public_ip" {
  description = "Public IP used by Kamal SSH and temporary DNS troubleshooting"
  value       = module.compute.public_ip
}

output "ec2_instance_id" {
  description = "EC2 instance ID"
  value       = module.compute.instance_id
}

output "rds_endpoint" {
  description = "RDS endpoint"
  value       = module.rds.endpoint
}

output "rds_port" {
  description = "RDS port"
  value       = module.rds.port
}

output "ecr_repository_url" {
  description = "ECR repository URL for Kamal"
  value       = module.ecr.repository_url
}

output "dns_fqdn" {
  description = "Created DNS record FQDN"
  value       = try(module.dns[0].fqdn, null)
}

output "cognito_user_pool_id" {
  description = "Cognito User Pool ID"
  value       = module.cognito.user_pool_id
}

output "cognito_client_id" {
  description = "Cognito App Client ID"
  value       = module.cognito.client_id
}

output "cognito_domain" {
  description = "Cognito domain prefix"
  value       = module.cognito.domain
}

output "cognito_region" {
  description = "Cognito AWS region"
  value       = module.cognito.region
}

output "rds_master_secret_arn" {
  description = "RDS-managed master user password secret ARN"
  value       = module.rds.master_user_secret_arn
}

output "rails_master_key_secret_arn" {
  description = "Secrets Manager ARN for Rails master key"
  value       = aws_secretsmanager_secret.rails_master_key.arn
}

output "app_env_secret_arn" {
  description = "Secrets Manager ARN for application env vars"
  value       = aws_secretsmanager_secret.app_env.arn
}

output "cognito_client_secret_secret_arn" {
  description = "Secrets Manager ARN where Cognito client secret should be stored"
  value       = aws_secretsmanager_secret.cognito_client_secret.arn
}

output "database_names" {
  description = "Database names used by primary/cache/queue/cable in staging"
  value = {
    primary = var.primary_database_name
    cache   = var.cache_database_name
    queue   = var.queue_database_name
    cable   = var.cable_database_name
  }
}

output "database_url_templates" {
  description = "Connection URL templates without passwords (replace __PASSWORD__ securely at runtime)"
  value = {
    primary = "postgresql://${var.rds_master_username}:__PASSWORD__@${module.rds.address}:${module.rds.port}/${var.primary_database_name}"
    cache   = "postgresql://${var.rds_master_username}:__PASSWORD__@${module.rds.address}:${module.rds.port}/${var.cache_database_name}"
    queue   = "postgresql://${var.rds_master_username}:__PASSWORD__@${module.rds.address}:${module.rds.port}/${var.queue_database_name}"
    cable   = "postgresql://${var.rds_master_username}:__PASSWORD__@${module.rds.address}:${module.rds.port}/${var.cable_database_name}"
  }
}
