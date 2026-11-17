import json
import os
import uuid
import urllib.parse
from datetime import datetime, timezone
import boto3

s3_client = boto3.client('s3')
dynamodb = boto3.resource('dynamodb')
sns_client = boto3.client('sns')

DYNAMODB_TABLE = os.environ['DYNAMODB_TABLE']
SNS_TOPIC_ARN = os.environ['SNS_TOPIC_ARN']

def lambda_handler(event, context):
    print("Received EventBridge Event:", json.dumps(event))
    
    # Extract metadata from the EventBridge payload
    detail = event.get('detail', {})
    bucket_name = detail.get('bucket', {}).get('name')
    raw_key = detail.get('object', {}).get('key', '')
    object_key = urllib.parse.unquote_plus(raw_key)
    object_size = int(detail.get('object', {}).get('size', 0))
    event_time = event.get('time', datetime.now(timezone.utc).isoformat())

    # Fetch the actual file from S3
    response = s3_client.get_object(Bucket=bucket_name, Key=object_key)
    content_type = response.get('ContentType', 'application/octet-stream')
    raw_body = response['Body'].read().decode('utf-8', errors='replace')

    # Attempt to parse as JSON, fallback to raw text if not JSON
    try:
        parsed_json = json.loads(raw_body)
        record_summary = f"Valid JSON payload with {len(parsed_json)} top-level keys."
        extracted_data = json.dumps(parsed_json)
    except Exception:
        line_count = len(raw_body.splitlines())
        record_summary = f"Text/Binary file processed ({line_count} lines)."
        extracted_data = raw_body[:250]

    record_id = f"EVT-{uuid.uuid4().hex[:8].upper()}"
    processed_at = datetime.now(timezone.utc).isoformat()

    # Prepare the item for DynamoDB
    item = {
        'RecordId': record_id,
        'BucketName': bucket_name,
        'ObjectKey': object_key,
        'ObjectSizeBytes': object_size,
        'ContentType': content_type,
        'EventTimestamp': event_time,
        'ProcessedTimestamp': processed_at,
        'ProcessingSummary': record_summary,
        'PayloadPreview': extracted_data,
        'Status': 'PROCESSED_SUCCESS'
    }

    # Save to DynamoDB
    table = dynamodb.Table(DYNAMODB_TABLE)
    table.put_item(Item=item)
    
    # Format and send the SNS Email Alert
    email_message = (
        f"⚡ AWS Event-Driven Pipeline Notification\n"
        f"==========================================\n"
        f"Status:            SUCCESS\n"
        f"Record ID:         {record_id}\n"
        f"S3 Bucket:         {bucket_name}\n"
        f"File Uploaded:     {object_key}\n"
        f"File Size:         {object_size} bytes\n"
        f"Processed At:      {processed_at}\n"
        f"Summary:           {record_summary}\n\n"
        f"Payload Preview:\n{extracted_data}\n"
        f"==========================================\n"
        f"Zero polling. Zero wasted compute."
    )

    sns_client.publish(
        TopicArn=SNS_TOPIC_ARN,
        Subject=f"[EDA Pipeline] Processed: {object_key} ({record_id})",
        Message=email_message
    )

    return {
        'statusCode': 200,
        'body': json.dumps({'RecordId': record_id, 'Status': 'PROCESSED_SUCCESS'})
    }