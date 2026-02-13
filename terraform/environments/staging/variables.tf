variable "project_name" {
  description = "Project name used in resource names"
  type        = string
  default     = "balansi"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "staging"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "sa-east-1"
}

variable "vpc_cidr" {
  description = "VPC CIDR"
  type        = string
  default     = "10.30.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "Two public subnet CIDRs"
  type        = list(string)
  default     = ["10.30.1.0/24", "10.30.2.0/24"]
}

variable "private_db_subnet_cidrs" {
  description = "Two private DB subnet CIDRs"
  type        = list(string)
  default     = ["10.30.11.0/24", "10.30.12.0/24"]
}

variable "ssh_cidr_blocks" {
  description = "CIDRs allowed to SSH"
  type        = list(string)
}

variable "ec2_instance_type" {
  description = "Staging EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "ec2_key_name" {
  description = "EC2 key pair name"
  type        = string
  default     = null
}

variable "ec2_root_volume_size" {
  description = "EC2 root volume size in GiB"
  type        = number
  default     = 30
}

variable "rds_master_username" {
  description = "RDS master username"
  type        = string
  default     = "balansi"
}

variable "rds_master_password" {
  description = "RDS master password. Leave null when rds_manage_master_user_password is true."
  type        = string
  default     = null
  sensitive   = true
}

variable "rds_manage_master_user_password" {
  description = "Let RDS manage master password in AWS Secrets Manager"
  type        = bool
  default     = true
}

variable "rds_master_user_secret_kms_key_id" {
  description = "Optional KMS key ID/ARN for the RDS-managed secret"
  type        = string
  default     = null
}

variable "rds_engine_version" {
  description = "PostgreSQL engine version (null = AWS default)"
  type        = string
  default     = null
}

variable "rds_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t4g.micro"
}

variable "rds_allocated_storage" {
  description = "Initial RDS storage in GiB"
  type        = number
  default     = 20
}

variable "rds_max_allocated_storage" {
  description = "Max RDS autoscaled storage in GiB"
  type        = number
  default     = 100
}

variable "rds_backup_retention_period" {
  description = "RDS backup retention in days"
  type        = number
  default     = 3
}

variable "rds_deletion_protection" {
  description = "RDS deletion protection"
  type        = bool
  default     = true
}

variable "rds_skip_final_snapshot" {
  description = "Skip final snapshot on destroy"
  type        = bool
  default     = false
}

variable "primary_database_name" {
  description = "Primary database name used by Rails"
  type        = string
  default     = "balansi_staging"
}

variable "cache_database_name" {
  description = "Cache database name used by Solid Cache"
  type        = string
  default     = "balansi_staging_cache"
}

variable "queue_database_name" {
  description = "Queue database name used by Solid Queue"
  type        = string
  default     = "balansi_staging_queue"
}

variable "cable_database_name" {
  description = "Cable database name used by Action Cable"
  type        = string
  default     = "balansi_staging_cable"
}

variable "ecr_repository_name" {
  description = "ECR repository name"
  type        = string
  default     = "balansi-staging"
}

variable "route53_zone_id" {
  description = "Route53 hosted zone ID. Leave empty to skip DNS record creation"
  type        = string
  default     = ""
}

variable "app_domain" {
  description = "FQDN used by staging app (e.g., staging.example.com)"
  type        = string
  default     = "staging.balansi.me"
}

variable "cognito_callback_urls" {
  description = "Allowed callback URLs for Cognito app client. Leave empty to auto-generate from app_domain."
  type        = list(string)
  default     = []
}

variable "cognito_logout_urls" {
  description = "Allowed logout URLs for Cognito app client. Leave empty to auto-generate from app_domain."
  type        = list(string)
  default     = []
}
