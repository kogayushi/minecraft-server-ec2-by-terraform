import boto3
import os

def lambda_handler(event, context):
    ec2_client = boto3.client('ec2')
    instance_id = os.environ['EC2_INSTANCE_ID']

    try:
        response = ec2_client.start_instances(InstanceIds=[instance_id])
        return {
            "statusCode": 200,
            "body": "Successfully started EC2 instance."
        }
    except Exception as e:
        return {
            "statusCode": 500,
            "body": f"Error starting EC2 instance: {str(e)}"
        }