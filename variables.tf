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
  description = "EventBridge cron expression"
  type        = string
  default     = "cron(0 0 * * ? *)"
}

variable "retention_days" {
  description = "Snapshot retention period"
  type        = number
  default     = 7
}
