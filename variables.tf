variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "backup_schedule" {
  description = "AWS Backup cron expression for daily backups"
  type        = string
  default     = "cron(0 2 * * ? *)"  # Daily at 2 AM UTC
}

variable "retention_days" {
  description = "Backup retention period in days"
  type        = number
  default     = 7
}
