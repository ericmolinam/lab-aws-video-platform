"""Transcoding worker: pulls jobs from the SQS queue fed by the raw bucket.

Stand-in for a real transcoding service (AWS Elemental MediaConvert, not
available in eu-south-2): it "produces" each rendition by copying the master
into the encoded bucket, then marks the video as ready in the metadata DB.
"""

import json
import os
import urllib.parse

import boto3

ENCODED_BUCKET = os.environ["ENCODED_BUCKET"]
RENDITIONS = os.environ["RENDITIONS"].split(",")

s3 = boto3.client("s3")
table = boto3.resource("dynamodb").Table(os.environ["TABLE_NAME"])


def handler(event, context):
    for record in event["Records"]:
        body = json.loads(record["body"])
        # S3 sends a test event when the notification is configured.
        for s3_event in body.get("Records", []):
            bucket = s3_event["s3"]["bucket"]["name"]
            key = urllib.parse.unquote_plus(s3_event["s3"]["object"]["key"])
            transcode(bucket, key)


def transcode(bucket, key):
    video_id = key.split("/")[0]

    table.update_item(
        Key={"video_id": video_id},
        UpdateExpression="SET #s = :s",
        ExpressionAttributeNames={"#s": "status"},
        ExpressionAttributeValues={":s": "transcoding"},
    )

    for rendition in RENDITIONS:
        s3.copy_object(
            CopySource={"Bucket": bucket, "Key": key},
            Bucket=ENCODED_BUCKET,
            Key=f"{video_id}/{rendition}.mp4",
        )

    table.update_item(
        Key={"video_id": video_id},
        UpdateExpression="SET #s = :s, renditions = :r",
        ExpressionAttributeNames={"#s": "status"},
        ExpressionAttributeValues={":s": "ready", ":r": RENDITIONS},
    )
