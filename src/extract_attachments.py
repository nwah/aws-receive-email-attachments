import os
import boto3
import json
import email
from email.policy import default
from io import BytesIO

SRC_BUCKET = os.environ['SRC_BUCKET']
SRC_PREFIX = os.environ.get('SRC_PREFIX', 'incoming-emails')
DEST_BUCKET = os.environ.get('DEST_BUCKET', SRC_BUCKET)
DEST_PREFIX = os.environ.get('DEST_PREFIX', SRC_PREFIX)

s3 = boto3.client("s3")

def lambda_handler(event, context):
    notification = json.loads(event['Records'][0]['Sns']['Message'])
    email_id = notification['mail']['messageId']
    print(f"Processing message {email_id}")
    object_name = f"{SRC_PREFIX}/{email_id}"
    
    # Read raw email bytes from S3 into memory
    raw_email = BytesIO()
    s3.download_fileobj(SRC_BUCKET, object_name, raw_email)

    # Reset stream and parse raw email
    raw_email.seek(0)
    msg = email.message_from_binary_file(raw_email, policy=default)

    # Save any file attachments with their original filename(s)
    for attachment in msg.iter_attachments():
        filename = attachment.get_filename()
        if filename:
            f = BytesIO(attachment.get_content())
            s3.upload_fileobj(f, DEST_BUCKET, f"{DEST_PREFIX}/{email_id}/{filename}")