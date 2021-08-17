import requests
import json
import boto3
coinbase_uri = 'https://api.coindesk.com/v1/bpi/currentprice.json'

def handler(event, context):
    AWS_BUCKET_NAME = 'bpi-price-bucket-00001'
    s3 = boto3.resource('s3')
    bucket = s3.Bucket(AWS_BUCKET_NAME)
    content = requests.get(coinbase_uri).json()
    path = f"{content['time']['updated']} BPI.json"
    data = json.dumps(content)
    bucket.put_object(
        ACL='public-read',
        ContentType='application/json',
        Key=path,
        Body=data,
    )