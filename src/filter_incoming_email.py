import boto3
import json

dynamo = boto3.client('dynamodb')

DDB_TABLE_NAME = os.environ('DDB_TABLE_NAME')

def lambda_handler(event, context):
    source = event['Records'][0]['ses']['mail']['source']
    print("Incoming mail from: " + source)

    # Attempt to get record from allow list Dynamo table, and ensure allow=True
    user = dynamo.get_item(TableName=DDB_TABLE_NAME, Key={'sender': {'S': source}}).get('Item')
    if not user or user['allow']['BOOL'] != True:
        print("--> REJECTING (" + ("Unknown user" if not user else "User not allowed") + ")")
        return {'disposition':'STOP_RULE_SET'}
    
    print("--> Allowed")