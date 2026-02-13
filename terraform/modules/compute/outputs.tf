output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.app.id
}

output "private_ip" {
  description = "EC2 private IP"
  value       = aws_instance.app.private_ip
}

output "public_ip" {
  description = "EC2 public IP"
  value       = try(aws_eip.app[0].public_ip, aws_instance.app.public_ip)
}

output "instance_profile_name" {
  description = "IAM instance profile name used by EC2"
  value       = var.create_instance_profile ? aws_iam_instance_profile.instance[0].name : var.instance_profile_name
}
