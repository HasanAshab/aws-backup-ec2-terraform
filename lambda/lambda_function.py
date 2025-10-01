import os
import boto3
import datetime

ec2 = boto3.client("ec2")
s3 = boto3.client("s3")
RETENTION_DAYS = 7
LOG_BUCKET = os.environ["LOG_BUCKET"]


def lambda_handler(event, context):
    logs = []
    reservations = ec2.describe_instances(
        Filters=[{"Name": "tag:Backup", "Values": ["true"]}]
    ).get("Reservations", [])

    for reservation in reservations:
        for instance in reservation["Instances"]:
            instance_id = instance["InstanceId"]
            for volume in instance["BlockDeviceMappings"]:
                vol_id = volume["Ebs"]["VolumeId"]
                snap = ec2.create_snapshot(
                    VolumeId=vol_id,
                    Description=f"Backup of {instance_id}, volume {vol_id}"
                )
                ec2.create_tags(
                    Resources=[snap["SnapshotId"]],
                    Tags=[
                        {"Key": "Name", "Value": f"{instance_id}-{vol_id}"},
                        {"Key": "CreatedOn", "Value": datetime.date.today().isoformat()}
                    ]
                )
                logs.append(f"Created snapshot {snap['SnapshotId']} for {instance_id}-{vol_id}")

    s3.put_object(Bucket=LOG_BUCKET, Key=f"backup-{datetime.datetime.now().isoformat()}.txt", Body="\n".join(logs))
