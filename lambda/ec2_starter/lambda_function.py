import boto3
import os
import json

def lambda_handler(event, context):
    ec2_instance_id = os.environ.get("EC2_INSTANCE_ID")

    if not ec2_instance_id:
        body = json.dumps({
            "message": "Error: EC2_INSTANCE_ID environment variable is not set."
        })
        return {
            "statusCode": 500,
            "body": body
        }

    ec2_client = boto3.client("ec2")

    # インスタンスを起動
    try:
        ec2_client.start_instances(InstanceIds=[ec2_instance_id])
        print(f"Starting EC2 instance {ec2_instance_id}. Waiting for it to be running...")

        # インスタンスが「running」状態になるまで待機
        waiter = ec2_client.get_waiter("instance_running")
        waiter.wait(InstanceIds=[ec2_instance_id])
    except Exception as e:
        print(f"Error starting EC2 instance: {str(e)}")
        body = json.dumps({
            "message": f"Error starting EC2 instance: {str(e)}"
        })
        return {
            "statusCode": 500,
            "body": body
        }

    # インスタンス情報を取得してパブリックIPを返す
    try:
        response = ec2_client.describe_instances(InstanceIds=[ec2_instance_id])
        instance = response["Reservations"][0]["Instances"][0]
        public_ip = instance.get("PublicIpAddress", "No public IP assigned")
        body = json.dumps({
            "message": "EC2 instance started successfully",
            "public_ip": public_ip
        })

        return {
            "statusCode": 200,
            "body": body
        }
    except Exception as e:
        print(f"Error fetching EC2 instance details: {str(e)}")
        body = json.dumps({
            "message": f"Error fetching EC2 instance details: {str(e)}"
        })
        return {
            "statusCode": 500,
            "body": body
        }