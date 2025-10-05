### Example EC2 instances ###
# The "BackupPlan" tag is used by AWS Backup to identify resources for backup
# For this example, we will create 3 instances,
# 2 of which will be backed up

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

module "ec2_instance" {
  source = "terraform-aws-modules/ec2-instance/aws"
  for_each = {
    "1" = "daily-backup"
    "2" = "daily-backup"
    "3" = "no-backup"
  }

  name          = "instance-${each.key}"
  instance_type = "t3.micro"
  subnet_id     = data.aws_subnets.default.ids[0]
  monitoring    = false

  tags = {
    BackupPlan = each.value
  }
}


### AWS Backup ###
# IAM role for AWS Backup service
resource "aws_iam_role" "backup_role" {
  name = "${local.project_name}-backup-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "backup.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "backup_policy" {
  role       = aws_iam_role.backup_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}

resource "aws_iam_role_policy_attachment" "restore_policy" {
  role       = aws_iam_role.backup_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores"
}

# Backup vault for storing backups
resource "aws_backup_vault" "main" {
  name        = "${local.project_name}-vault-${var.environment}"
  kms_key_arn = aws_kms_key.backup.arn

  tags = {
    Environment = var.environment
    Project     = local.project_name
  }
}

# KMS key for backup encryption
resource "aws_kms_key" "backup" {
  description             = "KMS key for ${local.project_name} backups"
  deletion_window_in_days = 7

  tags = {
    Environment = var.environment
    Project     = local.project_name
  }
}

resource "aws_kms_alias" "backup" {
  name          = "alias/${local.project_name}-backup-${var.environment}"
  target_key_id = aws_kms_key.backup.key_id
}

# Backup plan with lifecycle rules
resource "aws_backup_plan" "main" {
  name = "${local.project_name}-plan-${var.environment}"

  rule {
    rule_name         = "daily_backup_rule"
    target_vault_name = aws_backup_vault.main.name
    schedule          = var.backup_schedule

    lifecycle {
      delete_after = var.retention_days
    }

    recovery_point_tags = {
      Environment = var.environment
      Project     = local.project_name
      BackupType  = "automated"
    }
  }

  tags = {
    Environment = var.environment
    Project     = local.project_name
  }
}

# Backup selection - defines which resources to backup
resource "aws_backup_selection" "ec2_backup" {
  iam_role_arn = aws_iam_role.backup_role.arn
  name         = "${local.project_name}-ec2-selection-${var.environment}"
  plan_id      = aws_backup_plan.main.id

  selection_tag {
    type  = "STRINGEQUALS"
    key   = "BackupPlan"
    value = "daily-backup"
  }

  resources = ["*"]
}
