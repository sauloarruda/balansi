# Terraform Infrastructure as Code

This directory contains Terraform configurations for managing Balansi infrastructure, including AWS Cognito authentication.

## Directory Structure

```
terraform/
├── modules/
│   └── cognito/          # Reusable Cognito module
│       ├── main.tf       # Main resources
│       ├── variables.tf  # Input variables
│       ├── outputs.tf    # Output values
│       └── data.tf       # Data sources
└── environments/
    └── dev/              # Development environment
        ├── main.tf       # Environment-specific configuration
        └── outputs.tf    # Environment outputs
```

## Prerequisites

1. **Terraform**: Install Terraform >= 1.0
   ```bash
   # macOS
   brew install terraform
   
   # Or download from https://www.terraform.io/downloads
   ```

2. **AWS CLI**: Install and configure AWS credentials
   ```bash
   # macOS
   brew install awscli
   
   # Configure credentials
   aws configure
   ```

3. **AWS Account**: Ensure you have an AWS account with appropriate permissions for:
   - Creating Cognito User Pools
   - Creating Cognito User Pool Clients
   - Creating Cognito User Pool Domains

## Development Environment Setup

### Step 1: Initialize Terraform

Navigate to the development environment directory:

```bash
cd terraform/environments/dev
terraform init
```

This will download the required Terraform providers (AWS, random).

### Step 2: Review the Plan

Before applying, review what Terraform will create:

```bash
terraform plan
```

You should see:
- AWS Cognito User Pool (`balansi-users-dev`)
- AWS Cognito User Pool Client
- AWS Cognito User Pool Domain (default domain)

### Step 3: Apply Infrastructure

Create the infrastructure:

```bash
terraform apply
```

Type `yes` when prompted. This will create:
- Cognito User Pool with "name" and "email" as required attributes
- User Pool Client with OAuth settings
- Cognito domain for Hosted UI

**Note**: All resources are created in the `sa-east-1` (São Paulo) region to minimize latency for Brazilian users.

### Step 4: Get Outputs

After applying, get the Terraform outputs:

```bash
terraform output -json
```

This will output:
- `cognito_user_pool_id`: User Pool ID (e.g., `sa-east-1_XXXXXXXXX`)
- `cognito_client_id`: Client ID
- `cognito_client_secret`: Client Secret (sensitive)
- `cognito_domain`: Domain name (e.g., `balansi-dev-xxxxx` - note: this is just the domain name, Rails constructs the full URL)
- `cognito_region`: AWS region (`sa-east-1`)

### Step 5: Update Rails Credentials

1. Edit Rails credentials for development:
   ```bash
   bin/rails credentials:edit --environment development
   ```

2. Add Cognito configuration:
   ```yaml
   cognito:
     user_pool_id: sa-east-1_XXXXXXXXX  # From terraform output (cognito_user_pool_id)
     client_id: xxxxxxxxxxxxxxxxxxxxx    # From terraform output (cognito_client_id)
     client_secret: xxxxxxxxxxxxxxxxxxxxxx  # From terraform output (cognito_client_secret)
     domain: balansi-dev-xxxxx  # From terraform output (cognito_domain) - just the domain name
     region: sa-east-1  # From terraform output (cognito_region)
     redirect_uri: http://localhost:3000/auth/callback
     logout_uri: http://localhost:3000
   ```
   
   **Note**: The `domain` value should be just the domain name (e.g., `balansi-dev-xxxxx`), not the full URL. Rails CognitoService will construct the full URL using the format: `https://{domain}.auth.{region}.amazoncognito.com`

3. Save and close the editor (Rails will encrypt the file automatically)

**Note**: The master key for development credentials is stored locally in `config/master.key` (not version controlled). Each developer should have their own copy.

## Cognito Module

The `modules/cognito` directory contains a reusable Terraform module for creating Cognito infrastructure.

### Module Inputs

- `user_pool_name`: Name of the Cognito User Pool
- `project_name`: Project name (default: "balansi")
- `environment`: Environment name (dev, staging, production)
- `callback_urls`: List of allowed OAuth callback URLs
- `logout_urls`: List of allowed logout URLs
- `tags`: Tags to apply to resources

### Module Outputs

- `user_pool_id`: Cognito User Pool ID
- `client_id`: User Pool Client ID
- `client_secret`: User Pool Client Secret (sensitive)
- `domain`: Cognito User Pool Domain
- `region`: AWS region
- `user_pool_arn`: Cognito User Pool ARN

### Configuration Details

**User Pool:**
- Password policy: 8+ characters, uppercase, lowercase, number, special character
- Required attributes: `name`, `email`
- Email verification: Auto-verified via Cognito

**User Pool Client:**
- OAuth flow: Authorization code grant
- OAuth scopes: `openid`, `email`, `profile`
- Token validity:
  - Access token: 1 hour
  - ID token: 1 hour
  - Refresh token: 30 days (matches Rails session expiration)

**Domain:**
- Uses default Cognito domain (not custom domain)
- Format: `{project}-{environment}-{random}.auth.{region}.amazoncognito.com`

## Destroying Infrastructure

To destroy all infrastructure created by Terraform:

```bash
cd terraform/environments/dev
terraform destroy
```

**Warning**: This will permanently delete the Cognito User Pool and all users. Use with caution.

## State Management

### Local State (Default)

By default, Terraform stores state locally in `terraform.tfstate`. This is fine for development but not recommended for production.

### Remote State (Recommended for Production)

For production, configure remote state in `terraform/environments/dev/main.tf`:

```hcl
terraform {
  backend "s3" {
    bucket = "balansi-terraform-state"
    key    = "dev/cognito/terraform.tfstate"
    region = "sa-east-1"
    encrypt = true
  }
}
```

**Note**: Ensure the S3 bucket exists and is properly secured before enabling remote state.

## File Management

### Git Ignore

Terraform state files and sensitive data are automatically ignored via `.gitignore` files:

- **Root `.gitignore`**: Should include common Terraform patterns (e.g., `*.tfstate`, `*.tfstate.*`)
- **`terraform/.gitignore`**: Module-specific ignore patterns for Terraform directories

**Important**: Never commit:
- `.tfstate` files (contain sensitive infrastructure state)
- `.tfvars` files (may contain secrets)
- `.terraform/` directories (provider plugins, can be regenerated)
- `terraform.tfstate.lock.info` (state lock files)

Git automatically respects `.gitignore` files in subdirectories, so the `terraform/.gitignore` file will be used when working within the Terraform directory.

## Troubleshooting

### Authentication Errors

If you see authentication errors:

1. Verify AWS credentials are configured:
   ```bash
   aws sts get-caller-identity
   ```

2. Ensure your AWS user has the necessary permissions (IAM policies for Cognito)

### State Lock Errors

If you see "state locked" errors:

1. Check if another Terraform process is running
2. If not, manually unlock:
   ```bash
   terraform force-unlock <LOCK_ID>
   ```

### Domain Already Exists

If you see "domain already exists" errors:

1. Cognito domains must be globally unique
2. Delete the existing domain manually via AWS Console, or
3. Use a different project/environment name

## Next Steps

After setting up Cognito infrastructure:

1. ✅ Complete Step 1: Infrastructure Setup (this step)
2. Proceed to Step 2: Core Implementation (migrations, models, services)
3. Proceed to Step 3: Testing (unit tests)

See `doc/auth/erd.md` for the complete implementation plan.

## References

- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [AWS Cognito User Pool](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cognito_user_pool)
- [AWS Cognito User Pool Client](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cognito_user_pool_client)
- [Terraform Best Practices](https://www.terraform.io/docs/cloud/guides/recommended-practices/index.html)
