terraform {
  required_version = ">= 1.0"

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

  # Backend configuration (uncomment and configure when using remote state)
  # backend "s3" {
  #   bucket = "balansi-terraform-state"
  #   key    = "dev/cognito/terraform.tfstate"
  #   region = "sa-east-1"
  # }
}

provider "aws" {
  region = "sa-east-1"

  default_tags {
    tags = {
      Environment = "dev"
      Project     = "balansi"
      ManagedBy   = "terraform"
    }
  }
}

# Cognito module
module "cognito" {
  source = "../../modules/cognito"

  user_pool_name = "balansi-users-dev"
  project_name   = "balansi"
  environment    = "dev"

  # Development callback URLs
  callback_urls = [
    "http://localhost:3000/auth/callback"
  ]

  # Development logout URLs
  logout_urls = [
    "http://localhost:3000/"
  ]

  # Tags are inherited from provider default_tags (see provider block above)
  # We don't pass tags here to avoid duplication - provider default_tags apply automatically
  # If additional tags are needed, they can be passed via the tags variable
  tags = {}
}
