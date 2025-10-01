### Example EC2 instances ###
# The "Backup" tag is used to identify instances that should be backed up
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
  source  = "terraform-aws-modules/ec2-instance/aws"
  for_each = {
    "1" = "true"
    "2" = "true"
    "3" = "false"
  }

  name = "instance-${each.key}"
  instance_type = "t3.micro"
  subnet_id = data.aws_subnets.default.ids[0]
  monitoring    = false

  tags = {
    Backup = each.value
  }
}


### Lambda ###
# Lambda function to back up EC2 instances
module "lambda_function" {
  source  = "terraform-aws-modules/lambda/aws"
  version = "8.1.0"

  function_name = "${local.project_name}-backup-${var.environment}"
  source_path = "${path.module}/lambda/lambda_function.py"
  handler = "lambda_function.lambda_handler"
  runtime = "python3.12"

  attach_policy_json = true
  policy_json = templatefile("${path.module}/templates/lambda_policy.json", {
    log_bucket_arn = module.log_bucket.s3_bucket_arn
  })
  allowed_triggers = {
    eventbridge = {
      service    = "events"
      source_arn = module.eventbridge.eventbridge_rule_arns["crons"]
    }
  }

  create_current_version_allowed_triggers = false
  artifacts_dir = "${path.root}/.terraform/lambda-builds/"
  environment_variables = {
    ENVIRONMENT    = var.environment
    LOG_BUCKET = module.log_bucket.s3_bucket_id
  }
}


### Log bucket ###
# S3 bucket for storing backup logs
module "log_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "5.5.0"

  bucket = "${local.project_name}-log-${var.environment}"
  force_destroy = true
}


### EventBridge ###
# EventBridge to trigger backups
module "eventbridge" {
  source = "terraform-aws-modules/eventbridge/aws"

  create_bus = false
  rules = {
    crons = {
      description         = "Daily EC2 backup"
      schedule_expression = "cron(0 0 * * ? *)"
    }
  }
  targets = {
    crons = [
      {
        name = "ec2-backup-lambda"
        arn  = module.lambda_function.lambda_function_arn
      }
    ]
  }
}
