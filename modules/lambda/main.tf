module "lambda_function" {
  source  = "terraform-aws-modules/lambda/aws"
  version = "8.1.0"

  function_name = "${var.name_prefix}-backup-${var.environment}"
  source_path = var.source_path
  handler = var.handler
  runtime = var.runtime

  attach_policy_json = true
  policy_json = templatefile("${path.module}/templates/lambda_policy.json", {
    log_bucket_arn = module.log_bucket.s3_bucket_arn
  })
  # allowed_triggers = {
  #   apigw = {
  #     service    = "apigateway"
  #     source_arn = "${module.api_gateway.api_execution_arn}/*/*"
  #   }
  # }

  artifacts_dir = "${path.root}/.terraform/lambda-builds/"
  environment_variables = {
    ENVIRONMENT    = var.environment
    LOG_BUCKET = module.log_bucket.s3_bucket_id
  }
}

module "log_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "5.5.0"

  bucket = "${var.name_prefix}-log-${var.environment}"
  force_destroy = true
}
