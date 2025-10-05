# ------------------------------------------------------------------------------
# AWS Backup Solution Tests
# Validates the AWS Backup configuration and resources
# ------------------------------------------------------------------------------

run "validate_backup_plan" {
  command = plan

  assert {
    condition     = local.project_name == "aws-backup-solution"
    error_message = "Project name should be 'aws-backup-solution'"
  }

  assert {
    condition     = aws_backup_plan.main.rule[0].rule_name == "daily_backup_rule"
    error_message = "Backup plan rule name should be 'daily_backup_rule'"
  }

  assert {
    condition     = aws_backup_plan.main.rule[0].lifecycle[0].delete_after == var.retention_days
    error_message = "Backup retention should match the retention_days variable"
  }
}

run "validate_backup_selection" {
  command = plan

  assert {
    condition     = aws_backup_selection.ec2_backup.selection_tag[0].key == "BackupPlan"
    error_message = "Backup selection should target resources with 'BackupPlan' tag"
  }

  assert {
    condition     = aws_backup_selection.ec2_backup.selection_tag[0].value == "daily-backup"
    error_message = "Backup selection should target resources with 'daily-backup' tag value"
  }
}

run "validate_kms_encryption" {
  command = plan

  assert {
    condition     = aws_backup_vault.main.kms_key_arn == aws_kms_key.backup.arn
    error_message = "Backup vault should use the created KMS key for encryption"
  }
}
