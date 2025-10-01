
### Example EC2 instances ###
# The "Backup" tag is used to identify instances that should be backed up
# For this example, we will create 3 instances,
# 2 of which will be backed up

module "ec2_instance" {
  source  = "terraform-aws-modules/ec2-instance/aws"
  for_each = {
    "1" = "true"
    "2" = "true"
    "3" = "false"
  }

  name = "instance-${each.key}"

  instance_type = "t3.micro"
  create_security_group = false
  monitoring    = false

  tags = {
    Backup = each.value
  }
}


### Lambda ###
# Lambda function to back up EC2 instances
module "lambda" {
  source = "./modules/lambda"

  environment = var.environment
  name_prefix = local.project_name

  source_path = "${path.root}/lambda"
  handler = "lambda_function.lambda_handler"
}
