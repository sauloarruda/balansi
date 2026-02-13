locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

resource "aws_iam_role" "instance" {
  count = var.create_instance_profile ? 1 : 0

  name = "${local.name_prefix}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-ec2-role"
  })
}

resource "aws_iam_role_policy_attachment" "ssm" {
  count = var.create_instance_profile && var.enable_ssm ? 1 : 0

  role       = aws_iam_role.instance[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "ecr_read" {
  count = var.create_instance_profile && var.enable_ecr_read ? 1 : 0

  role       = aws_iam_role.instance[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

data "aws_iam_policy_document" "runtime_secrets_access" {
  count = var.create_instance_profile && var.runtime_secrets_policy_enabled ? 1 : 0

  dynamic "statement" {
    for_each = length(var.secrets_manager_secret_arns) > 0 ? [1] : []
    content {
      sid    = "ReadAllowedSecretsManagerSecrets"
      effect = "Allow"
      actions = [
        "secretsmanager:DescribeSecret",
        "secretsmanager:GetSecretValue"
      ]
      resources = var.secrets_manager_secret_arns
    }
  }

  dynamic "statement" {
    for_each = length(var.ssm_parameter_arns) > 0 ? [1] : []
    content {
      sid    = "ReadAllowedSsmParameters"
      effect = "Allow"
      actions = [
        "ssm:GetParameter",
        "ssm:GetParameters",
        "ssm:GetParameterHistory"
      ]
      resources = var.ssm_parameter_arns
    }
  }

  dynamic "statement" {
    for_each = length(var.kms_key_arns) > 0 ? [1] : []
    content {
      sid    = "DecryptAllowedKmsKeys"
      effect = "Allow"
      actions = [
        "kms:Decrypt"
      ]
      resources = var.kms_key_arns
    }
  }
}

resource "aws_iam_policy" "runtime_secrets_access" {
  count = var.create_instance_profile && var.runtime_secrets_policy_enabled ? 1 : 0

  name   = "${local.name_prefix}-runtime-secrets-access"
  policy = data.aws_iam_policy_document.runtime_secrets_access[0].json

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-runtime-secrets-access"
  })
}

resource "aws_iam_role_policy_attachment" "runtime_secrets_access" {
  count = var.create_instance_profile && var.runtime_secrets_policy_enabled ? 1 : 0

  role       = aws_iam_role.instance[0].name
  policy_arn = aws_iam_policy.runtime_secrets_access[0].arn
}

resource "aws_iam_instance_profile" "instance" {
  count = var.create_instance_profile ? 1 : 0

  name = "${local.name_prefix}-ec2-profile"
  role = aws_iam_role.instance[0].name

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-ec2-profile"
  })
}

resource "aws_instance" "app" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = var.security_group_ids
  key_name               = var.key_name

  iam_instance_profile = var.create_instance_profile ? aws_iam_instance_profile.instance[0].name : var.instance_profile_name

  user_data                   = var.user_data
  user_data_replace_on_change = true

  root_block_device {
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
    delete_on_termination = true
    encrypted             = true
  }

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-app"
  })
}

resource "aws_eip" "app" {
  count = var.create_elastic_ip ? 1 : 0

  domain   = "vpc"
  instance = aws_instance.app.id

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-app-eip"
  })
}
