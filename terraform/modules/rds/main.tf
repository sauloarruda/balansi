locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

resource "aws_db_subnet_group" "main" {
  name       = "${local.name_prefix}-db-subnet-group"
  subnet_ids = var.subnet_ids

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-db-subnet-group"
  })
}

resource "aws_db_instance" "main" {
  identifier                    = var.identifier
  engine                        = "postgres"
  engine_version                = var.engine_version
  instance_class                = var.instance_class
  allocated_storage             = var.allocated_storage
  max_allocated_storage         = var.max_allocated_storage
  storage_type                  = "gp3"
  storage_encrypted             = true
  db_name                       = var.db_name
  username                      = var.username
  password                      = var.manage_master_user_password ? null : var.password
  manage_master_user_password   = var.manage_master_user_password
  master_user_secret_kms_key_id = var.master_user_secret_kms_key_id
  db_subnet_group_name          = aws_db_subnet_group.main.name
  vpc_security_group_ids        = var.vpc_security_group_ids
  backup_retention_period       = var.backup_retention_period
  deletion_protection           = var.deletion_protection
  skip_final_snapshot           = var.skip_final_snapshot
  publicly_accessible           = false
  multi_az                      = false
  auto_minor_version_upgrade    = true
  apply_immediately             = true

  lifecycle {
    precondition {
      condition     = var.manage_master_user_password || try(length(var.password), 0) >= 8
      error_message = "Set password with at least 8 characters when manage_master_user_password is false."
    }
  }

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-postgres"
  })
}
