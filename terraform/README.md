# Terraform Infrastructure

This directory contains Terraform configurations for Balansi infrastructure.

## Scope

Terraform is used for AWS infrastructure:
- VPC and networking
- EC2
- RDS PostgreSQL
- ECR
- Route53
- supporting secrets in AWS Secrets Manager

The Rails authentication flow is implemented inside the app, so local development does not depend on Terraform.

## Directory Structure

```text
terraform/
├── modules/
│   ├── compute/
│   ├── dns/
│   ├── ecr/
│   ├── network/
│   └── rds/
└── environments/
    └── staging/
```

## Staging Workflow

```bash
cd terraform/environments/staging
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform plan
terraform apply
```

Useful outputs after apply:

```bash
terraform output
terraform output -raw ecr_repository_url
terraform output -raw rds_master_secret_arn
terraform output -raw rails_master_key_secret_arn
terraform output -raw app_env_secret_arn
```

## Local Development

To run the app locally:

```bash
bundle install
bin/rails db:prepare
bin/dev
```

## Prerequisites

- Terraform >= 1.0
- AWS CLI configured with credentials that can manage the target environment
- Access to the AWS account used by Balansi infrastructure

## Destroying Infrastructure

Use Terraform from the target environment directory:

```bash
cd terraform/environments/staging
terraform destroy
```

Review the plan carefully before applying destructive changes.
