variable "project_name" {
  description = "Project name used in resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID where the instance will be created"
  type        = string
}

variable "security_group_ids" {
  description = "Security groups attached to the instance"
  type        = list(string)
}

variable "ami_id" {
  description = "AMI ID used by EC2 instance"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "key_name" {
  description = "Optional SSH key pair name"
  type        = string
  default     = null
}

variable "root_volume_size" {
  description = "Root volume size in GiB"
  type        = number
  default     = 20
}

variable "user_data" {
  description = "User data script"
  type        = string
  default     = ""
}

variable "create_instance_profile" {
  description = "Whether to create IAM instance profile automatically"
  type        = bool
  default     = true
}

variable "instance_profile_name" {
  description = "Existing IAM instance profile name when create_instance_profile is false"
  type        = string
  default     = null
}

variable "enable_ssm" {
  description = "Attach SSM managed policy to instance role"
  type        = bool
  default     = true
}

variable "enable_ecr_read" {
  description = "Attach ECR read-only policy to instance role"
  type        = bool
  default     = true
}

variable "create_elastic_ip" {
  description = "Allocate and associate Elastic IP"
  type        = bool
  default     = true
}

variable "secrets_manager_secret_arns" {
  description = "Secrets Manager secret ARNs that EC2 can read"
  type        = list(string)
  default     = []
}

variable "ssm_parameter_arns" {
  description = "SSM parameter ARNs that EC2 can read"
  type        = list(string)
  default     = []
}

variable "kms_key_arns" {
  description = "KMS key ARNs EC2 can use for decrypting secrets/parameters"
  type        = list(string)
  default     = []
}

variable "runtime_secrets_policy_enabled" {
  description = "Whether to create and attach an IAM policy for runtime secret/parameter access"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
