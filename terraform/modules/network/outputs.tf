output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = aws_subnet.public[*].id
}

output "private_db_subnet_ids" {
  description = "Private DB subnet IDs"
  value       = aws_subnet.private_db[*].id
}

output "app_security_group_id" {
  description = "Security group ID for app"
  value       = aws_security_group.app.id
}

output "db_security_group_id" {
  description = "Security group ID for DB"
  value       = aws_security_group.db.id
}
