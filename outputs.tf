output "backup_vault_name" {
  description = "Name of the AWS Backup vault"
  value       = aws_backup_vault.main.name
}

output "backup_plan_id" {
  description = "ID of the AWS Backup plan"
  value       = aws_backup_plan.main.id
}

output "backup_vault_arn" {
  description = "ARN of the AWS Backup vault"
  value       = aws_backup_vault.main.arn
}

output "kms_key_id" {
  description = "ID of the KMS key used for backup encryption"
  value       = aws_kms_key.backup.key_id
}

output "ec2_instances" {
  description = "Map of EC2 instances and their backup configuration"
  value = {
    for k, v in module.ec2_instance : k => {
      instance_id = v.id
      backup_plan = v.tags.BackupPlan
    }
  }
}
