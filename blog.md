# Automate EC2 Backups on AWS with Lambda, EventBridge, and Terraform

*Stop losing sleep over manual backups. Here's how to build a bulletproof, serverless EC2 backup system that runs itself.*

---

Picture this: It's 3 AM, your production server crashes, and you realize your last backup was... when exactly? We've all been there. Manual backups are like flossing – everyone knows they should do it, but somehow it never happens consistently.

Today, I'll show you how to build a completely automated EC2 backup system using AWS Lambda, EventBridge, and Terraform. By the end of this guide, you'll have a system that:

- Backs up your EC2 instances every night automatically
- Cleans up old snapshots to save costs
- Logs everything for audit trails
- Requires zero maintenance once deployed

The best part? It costs pennies to run and takes about 15 minutes to set up.

## Why This Approach Works

Before we dive in, let's talk about why this serverless approach beats traditional backup solutions:

**Cost-Effective**: You only pay for what you use. No expensive backup software licenses or dedicated servers.

**Reliable**: AWS manages the infrastructure. No more "backup server is down" emergencies.

**Scalable**: Works whether you have 5 instances or 500. The system scales automatically.

**Auditable**: Every backup operation is logged and tracked.

## The Architecture (Keep It Simple)

Our backup system has four main components:

1. **EventBridge**: Acts like a cron job, triggering backups daily
2. **Lambda Function**: The workhorse that creates and manages snapshots
3. **EC2 Tags**: Simple way to mark which instances need backing up
4. **S3 Bucket**: Stores backup logs for auditing

Here's how they work together:

```
EventBridge (Daily) → Lambda → Find Tagged EC2s → Create Snapshots → Log to S3
```

No complex orchestration, no fragile dependencies. Just simple, reliable automation.

## What You'll Need

Before we start, make sure you have:

- AWS CLI configured with admin permissions
- Terraform installed (version 1.0 or later)
- Basic familiarity with AWS services
- About 15 minutes of your time

Don't worry if you're new to some of these tools – I'll walk you through everything.

## Step 1: Project Structure

Let's start by creating our project structure. This keeps everything organized and makes the code reusable:

```
ec2-backup-automation/
├── main.tf                    # Main Terraform configuration
├── variables.tf               # Input variables
├── terraform.tfvars          # Your specific values
├── lambda/
│   └── lambda_function.py    # Backup logic
└── templates/
    └── lambda_policy.json    # IAM permissions
```

Create this structure on your machine:

```bash
mkdir ec2-backup-automation
cd ec2-backup-automation
mkdir lambda templates
```

## Step 2: The Lambda Function (The Heart of the System)

The Lambda function is where the magic happens. It finds EC2 instances tagged for backup, creates snapshots, and cleans up old ones.

Create `lambda/lambda_function.py`:

```python
import os
import boto3
import datetime
from typing import List, Dict

# Initialize AWS clients
ec2 = boto3.client("ec2")
s3 = boto3.client("s3")

# Environment variables
RETENTION_DAYS = int(os.environ["RETENTION_DAYS"])
LOG_BUCKET = os.environ["LOG_BUCKET"]

def lambda_handler(event, context):
    """
    Main Lambda handler - creates backups and cleans up old snapshots
    """
    logs = []

    try:
        # Step 1: Create new backups
        backup_logs = create_backups()
        logs.extend(backup_logs)

        # Step 2: Clean up old snapshots
        cleanup_logs = cleanup_old_snapshots()
        logs.extend(cleanup_logs)

        # Step 3: Save logs to S3
        save_logs_to_s3(logs)

        return {
            'statusCode': 200,
            'body': f'Backup completed successfully. {len(backup_logs)} snapshots created.'
        }

    except Exception as e:
        error_msg = f"Backup failed: {str(e)}"
        logs.append(error_msg)
        save_logs_to_s3(logs)
        raise

def create_backups() -> List[str]:
    """
    Find EC2 instances tagged for backup and create snapshots
    """
    logs = []

    # Find all instances tagged with Backup=true
    reservations = ec2.describe_instances(
        Filters=[{"Name": "tag:Backup", "Values": ["true"]}]
    ).get("Reservations", [])

    if not reservations:
        logs.append("No instances found with Backup=true tag")
        return logs

    for reservation in reservations:
        for instance in reservation["Instances"]:
            instance_id = instance["InstanceId"]

            # Skip terminated instances
            if instance["State"]["Name"] == "terminated":
                continue

            # Create snapshots for each EBS volume
            for volume in instance.get("BlockDeviceMappings", []):
                if "Ebs" not in volume:
                    continue

                vol_id = volume["Ebs"]["VolumeId"]

                try:
                    # Create the snapshot
                    snapshot = ec2.create_snapshot(
                        VolumeId=vol_id,
                        Description=f"Automated backup of {instance_id}, volume {vol_id}"
                    )

                    # Tag the snapshot for identification and cleanup
                    ec2.create_tags(
                        Resources=[snapshot["SnapshotId"]],
                        Tags=[
                            {"Key": "Name", "Value": f"backup-{instance_id}-{vol_id}"},
                            {"Key": "InstanceId", "Value": instance_id},
                            {"Key": "VolumeId", "Value": vol_id},
                            {"Key": "CreatedBy", "Value": "automated-backup"},
                            {"Key": "CreatedOn", "Value": datetime.date.today().isoformat()}
                        ]
                    )

                    logs.append(f"✅ Created snapshot {snapshot['SnapshotId']} for {instance_id}/{vol_id}")

                except Exception as e:
                    logs.append(f"❌ Failed to backup {instance_id}/{vol_id}: {str(e)}")

    return logs

def cleanup_old_snapshots() -> List[str]:
    """
    Delete snapshots older than RETENTION_DAYS
    """
    logs = []
    cutoff_date = datetime.date.today() - datetime.timedelta(days=RETENTION_DAYS)

    try:
        # Find snapshots created by our backup system
        snapshots = ec2.describe_snapshots(
            OwnerIds=['self'],
            Filters=[
                {"Name": "tag:CreatedBy", "Values": ["automated-backup"]},
                {"Name": "status", "Values": ["completed"]}
            ]
        )["Snapshots"]

        for snapshot in snapshots:
            # Check if snapshot is old enough to delete
            created_on = None
            for tag in snapshot.get("Tags", []):
                if tag["Key"] == "CreatedOn":
                    created_on = datetime.datetime.strptime(tag["Value"], "%Y-%m-%d").date()
                    break

            if created_on and created_on < cutoff_date:
                try:
                    ec2.delete_snapshot(SnapshotId=snapshot["SnapshotId"])
                    logs.append(f"🗑️ Deleted old snapshot {snapshot['SnapshotId']} (created {created_on})")
                except Exception as e:
                    logs.append(f"❌ Failed to delete snapshot {snapshot['SnapshotId']}: {str(e)}")

    except Exception as e:
        logs.append(f"❌ Error during cleanup: {str(e)}")

    return logs

def save_logs_to_s3(logs: List[str]):
    """
    Save execution logs to S3 for auditing
    """
    timestamp = datetime.datetime.now().isoformat()
    log_content = f"EC2 Backup Report - {timestamp}\n" + "="*50 + "\n\n"
    log_content += "\n".join(logs)

    try:
        s3.put_object(
            Bucket=LOG_BUCKET,
            Key=f"backup-logs/{timestamp[:10]}/backup-{timestamp}.txt",
            Body=log_content,
            ContentType="text/plain"
        )
    except Exception as e:
        print(f"Failed to save logs to S3: {str(e)}")
```
## Step 3: IAM Permissions (Security Done Right)

Our Lambda needs specific permissions to do its job. Create `templates/lambda_policy.json`:

```json
{
  "Version": "2008-10-17",
  "Id": "PolicyForEC2AutoBackupLambda",
  "Statement": [
    {
      "Sid": "AllowLogging",
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:*:*:*"
    },
    {
      "Sid": "AllowEC2Actions",
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeInstances",
        "ec2:DescribeVolumes",
        "ec2:CreateSnapshot",
        "ec2:DescribeSnapshots",
        "ec2:DeleteSnapshot",
        "ec2:CreateTags"
      ],
      "Resource": "*"
    },
    {
      "Sid": "AllowPutS3",
      "Effect": "Allow",
      "Action": [
        "s3:PutObject"
      ],
      "Resource": "${log_bucket_arn}/*"
    }
  ]
}

```

This follows the principle of least privilege – the Lambda can only do what it needs to do, nothing more.

## Step 4: Terraform Configuration

Now let's tie everything together with Terraform. Create `variables.tf`:

```hcl
variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "ec2-backup"
}

variable "backup_schedule" {
  description = "EventBridge cron expression for backup schedule"
  type        = string
  default     = "cron(0 2 * * ? *)"  # 2 AM UTC daily
}

variable "retention_days" {
  description = "Number of days to retain snapshots"
  type        = number
  default     = 7
}
```

Now create `main.tf`. I'll break this down into logical sections so it's easier to understand:

### S3 Bucket for Logs

Next, we'll create an S3 bucket to store our backup logs:

```hcl
module "log_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "5.5.0"

  bucket = "${local.project_name}-log-${var.environment}"
  force_destroy = true
}
```

This creates a simple S3 bucket where our Lambda function will store detailed backup reports. The `force_destroy = true` allows Terraform to delete the bucket even if it contains files (useful for testing).

### Lambda Function

Now for the heart of our system - the Lambda function:

```hcl
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
    RETENTION_DAYS = var.retention_days
  }
}
```

This creates our Lambda function with:
- **Source code**: Points to our Python file
- **IAM permissions**: Uses the policy template we created
- **EventBridge trigger**: Allows EventBridge to invoke the function
- **Environment variables**: Passes configuration to our Python code

### EventBridge Scheduler

Finally, let's set up the scheduler that triggers our backups:

```hcl
module "eventbridge" {
  source = "terraform-aws-modules/eventbridge/aws"

  create_bus = false
  rules = {
    crons = {
      description         = "Daily EC2 backup"
      schedule_expression = var.backup_schedule
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
```

This creates an EventBridge rule that:
- **Runs on schedule**: Uses the cron expression from our variables
- **Targets our Lambda**: Automatically invokes our backup function
- **Uses default event bus**: No need for a custom event bus

### Example EC2 Instances (Optional)

For testing purposes, let's also create some sample EC2 instances:

```hcl
# Get default VPC and subnets for our test instances
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Create test instances - some will be backed up, some won't
module "ec2_instance" {
  source  = "terraform-aws-modules/ec2-instance/aws"
  for_each = {
    "1" = "true"   # This instance will be backed up
    "2" = "true"   # This instance will be backed up
    "3" = "false"  # This instance will NOT be backed up
  }

  name = "instance-${each.key}"
  instance_type = "t3.micro"
  subnet_id = data.aws_subnets.default.ids[0]
  monitoring = false

  tags = {
    Backup = each.value  # This is the magic tag!
  }
}
```

This creates three test instances in your default VPC. Two are tagged for backup (`Backup=true`) and one isn't (`Backup=false`). This lets you see the system in action without affecting your existing instances.


## Step 5: Configuration and Deployment

Create your `terraform.tfvars` file with your specific settings:

```hcl
region       = "us-east-1"
environment  = "production"
project_name = "my-ec2-backup"

# Backup at 2 AM UTC every day
backup_schedule = "cron(0 2 * * ? *)"

# Keep snapshots for 7 days
retention_days = 7
```

Now deploy everything:

```bash
# Initialize Terraform
terraform init

# Review what will be created
terraform plan

# Deploy the infrastructure
terraform apply
```

Terraform will show you exactly what it's going to create. Type `yes` when you're ready to proceed.

## Step 6: Test Your Backup System

Don't wait until disaster strikes to test your backups! Here's how to verify everything works:

**Trigger a manual backup:**
```bash
aws lambda invoke --function-name my-ec2-backup-production-backup response.json
cat response.json
```

**Check the logs:**
1. Go to CloudWatch → Log groups
2. Find `/aws/lambda/my-ec2-backup-production-backup`
3. Check the latest log stream

**Verify snapshots were created:**
1. Go to EC2 → Snapshots
2. Look for snapshots tagged with `CreatedBy=automated-backup`

**Check S3 logs:**
1. Go to S3 → your backup logs bucket
2. Look in the `backup-logs/` folder for detailed reports

## Monitoring and Maintenance

Your backup system is now running, but here are some tips to keep it healthy:

### Set Up Alerts

Create a CloudWatch alarm to notify you if backups fail:

```hcl
resource "aws_cloudwatch_metric_alarm" "backup_failures" {
  alarm_name          = "${local.project_name}-backup-failures"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "This metric monitors lambda errors"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    FunctionName = module.lambda_function.lambda_function_name
  }
}
```

### Cost Optimization

Monitor your snapshot costs and adjust retention as needed:

```bash
# Check snapshot costs
aws ce get-cost-and-usage \
  --time-period Start=2024-01-01,End=2024-01-31 \
  --granularity MONTHLY \
  --metrics BlendedCost \
  --group-by Type=DIMENSION,Key=SERVICE
```

### Regular Testing

Schedule monthly restore tests to ensure your backups actually work:

1. Create a test instance from a snapshot
2. Verify the instance boots and data is intact
3. Document the restore process

## Troubleshooting Common Issues

**Lambda timeout errors:**
- Increase the timeout in your Terraform configuration
- Consider splitting large backup jobs across multiple Lambda invocations

**Permission denied errors:**
- Check the IAM policy in `templates/lambda_policy.json`
- Ensure your AWS credentials have sufficient permissions

**Snapshots not being created:**
- Verify instances are tagged correctly (`Backup=true`)
- Check CloudWatch logs for specific error messages
- Ensure instances are in the same region as your Lambda

**EventBridge not triggering:**
- Verify the cron expression is correct
- Check that the Lambda permission allows EventBridge to invoke it

## What's Next?

You now have a production-ready EC2 backup system! Here are some enhancements you might consider:

**Multi-region backups:** Copy snapshots to another region for disaster recovery
**Slack notifications:** Get notified when backups complete or fail
**Backup verification:** Automatically test that snapshots are restorable
**Custom retention policies:** Different retention periods for different instance types
**Backup windows:** Only backup during specific time windows to reduce performance impact

## Wrapping Up

Building automated backups doesn't have to be complicated. With Lambda, EventBridge, and Terraform, you can create a robust, cost-effective backup system in under an hour.

The key benefits of this approach:

- **Set it and forget it**: Once deployed, it runs automatically
- **Cost-effective**: Pay only for what you use
- **Scalable**: Works for 5 instances or 500
- **Auditable**: Complete logs of every backup operation
- **Reliable**: Built on AWS managed services

Remember: The best backup system is the one that actually runs. Manual backups fail because humans forget. Automated backups succeed because computers don't.

Your future self (and your boss) will thank you when that inevitable "we need to restore from backup" moment arrives, and you can confidently say: "No problem, we have automated backups running every night."

Now go tag those instances and sleep better knowing your data is protected!

---

## Contact

*Have questions about this setup? Found a bug in the code? Drop a comment below

or reach out:
* **Website**: [hasan-ashab](https://hasan-ashab.vercel.app/)
* **LinkedIn**: [linkedin.com/in/hasan-ashab](https://linkedin.com/in/hasan-ashab/)
