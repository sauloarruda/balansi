output "instance_id" {
  description = "RDS instance identifier"
  value       = aws_db_instance.main.id
}

output "address" {
  description = "RDS hostname"
  value       = aws_db_instance.main.address
}

output "port" {
  description = "RDS port"
  value       = aws_db_instance.main.port
}

output "endpoint" {
  description = "RDS endpoint"
  value       = aws_db_instance.main.endpoint
}

output "db_name" {
  description = "Initial database name"
  value       = aws_db_instance.main.db_name
}

output "username" {
  description = "Master username"
  value       = aws_db_instance.main.username
}

output "master_user_secret_arn" {
  description = "ARN of RDS-managed master secret (null when disabled)"
  value       = try(aws_db_instance.main.master_user_secret[0].secret_arn, null)
}
