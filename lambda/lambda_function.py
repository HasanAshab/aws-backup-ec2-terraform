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

                    logs.append(f"Created snapshot {snapshot['SnapshotId']} for {instance_id}/{vol_id}")

                except Exception as e:
                    logs.append(f"Failed to backup {instance_id}/{vol_id}: {str(e)}")

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
                    logs.append(f"Deleted old snapshot {snapshot['SnapshotId']} (created {created_on})")
                except Exception as e:
                    logs.append(f"Failed to delete snapshot {snapshot['SnapshotId']}: {str(e)}")

    except Exception as e:
        logs.append(f"Error during cleanup: {str(e)}")

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
