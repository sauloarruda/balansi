variable "zone_id" {
  description = "Route53 hosted zone ID"
  type        = string
}

variable "record_name" {
  description = "DNS record name"
  type        = string
}

variable "ttl" {
  description = "DNS TTL"
  type        = number
  default     = 300
}

variable "records" {
  description = "Record values"
  type        = list(string)
}
