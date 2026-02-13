output "fqdn" {
  description = "Fully-qualified DNS name"
  value       = aws_route53_record.main.fqdn
}
