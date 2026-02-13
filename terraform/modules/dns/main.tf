resource "aws_route53_record" "main" {
  zone_id = var.zone_id
  name    = var.record_name
  type    = "A"
  ttl     = var.ttl
  records = var.records
}
