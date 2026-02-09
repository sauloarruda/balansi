terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }

  # Recommended for team usage (uncomment after creating bucket/table)
  # backend "s3" {
  #   bucket         = "balansi-terraform-state"
  #   key            = "staging/infrastructure.tfstate"
  #   region         = "sa-east-1"
  #   dynamodb_table = "balansi-terraform-locks"
  #   encrypt        = true
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ssm_parameter" "amazon_linux_2023_x86_64" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.1-x86_64"
}

locals {
  selected_azs = slice(data.aws_availability_zones.available.names, 0, 2)
  default_cognito_callback_urls = [
    "https://${var.app_domain}/auth/callback"
  ]
  default_cognito_logout_urls = [
    "https://${var.app_domain}/"
  ]

  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }

  runtime_secret_arns = concat(
    [
      aws_secretsmanager_secret.rails_master_key.arn,
      aws_secretsmanager_secret.app_env.arn,
      aws_secretsmanager_secret.cognito_client_secret.arn
    ],
    var.rds_manage_master_user_password ? [module.rds.master_user_secret_arn] : []
  )
}

resource "aws_secretsmanager_secret" "rails_master_key" {
  name        = "/${var.project_name}/${var.environment}/rails/master_key"
  description = "Rails master key for ${var.environment}"

  tags = local.common_tags
}

resource "aws_secretsmanager_secret" "app_env" {
  name        = "/${var.project_name}/${var.environment}/app/env"
  description = "Application environment variables for ${var.environment}"

  tags = local.common_tags
}

resource "aws_secretsmanager_secret" "cognito_client_secret" {
  name        = "/${var.project_name}/${var.environment}/cognito/client_secret"
  description = "Cognito app client secret for ${var.environment}"

  tags = local.common_tags
}

module "network" {
  source = "../../modules/network"

  project_name            = var.project_name
  environment             = var.environment
  vpc_cidr                = var.vpc_cidr
  availability_zones      = local.selected_azs
  public_subnet_cidrs     = var.public_subnet_cidrs
  private_db_subnet_cidrs = var.private_db_subnet_cidrs
  ssh_cidr_blocks         = var.ssh_cidr_blocks
  tags                    = local.common_tags
}

module "rds" {
  source = "../../modules/rds"

  project_name                  = var.project_name
  environment                   = var.environment
  identifier                    = "${var.project_name}-${var.environment}-postgres"
  db_name                       = var.primary_database_name
  username                      = var.rds_master_username
  password                      = var.rds_master_password
  manage_master_user_password   = var.rds_manage_master_user_password
  master_user_secret_kms_key_id = var.rds_master_user_secret_kms_key_id
  engine_version                = var.rds_engine_version
  instance_class                = var.rds_instance_class
  allocated_storage             = var.rds_allocated_storage
  max_allocated_storage         = var.rds_max_allocated_storage
  backup_retention_period       = var.rds_backup_retention_period
  deletion_protection           = var.rds_deletion_protection
  skip_final_snapshot           = var.rds_skip_final_snapshot
  subnet_ids                    = module.network.private_db_subnet_ids
  vpc_security_group_ids        = [module.network.db_security_group_id]
  tags                          = local.common_tags
}

module "ecr" {
  source = "../../modules/ecr"

  project_name    = var.project_name
  environment     = var.environment
  repository_name = var.ecr_repository_name
  tags            = local.common_tags
}

module "compute" {
  source = "../../modules/compute"

  project_name                   = var.project_name
  environment                    = var.environment
  subnet_id                      = module.network.public_subnet_ids[0]
  security_group_ids             = [module.network.app_security_group_id]
  ami_id                         = data.aws_ssm_parameter.amazon_linux_2023_x86_64.value
  instance_type                  = var.ec2_instance_type
  key_name                       = var.ec2_key_name
  root_volume_size               = var.ec2_root_volume_size
  user_data                      = <<-EOT
    #!/bin/bash
    set -euxo pipefail

    dnf update -y
    dnf install -y docker git

    systemctl enable docker
    systemctl start docker

    usermod -aG docker ec2-user
  EOT
  create_instance_profile        = true
  enable_ssm                     = true
  enable_ecr_read                = true
  runtime_secrets_policy_enabled = true
  secrets_manager_secret_arns    = local.runtime_secret_arns
  create_elastic_ip              = true
  tags                           = local.common_tags
}

module "dns" {
  count  = var.route53_zone_id == "" ? 0 : 1
  source = "../../modules/dns"

  zone_id     = var.route53_zone_id
  record_name = var.app_domain
  records     = [module.compute.public_ip]
}

module "cognito" {
  source = "../../modules/cognito"

  user_pool_name = "${var.project_name}-users-${var.environment}"
  project_name   = var.project_name
  environment    = var.environment
  callback_urls  = length(var.cognito_callback_urls) > 0 ? var.cognito_callback_urls : local.default_cognito_callback_urls
  logout_urls    = length(var.cognito_logout_urls) > 0 ? var.cognito_logout_urls : local.default_cognito_logout_urls
  tags           = local.common_tags
}
