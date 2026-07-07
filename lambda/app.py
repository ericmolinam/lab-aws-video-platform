"""App server: the /upload and /watch flows from the architecture.

POST /videos             -> register metadata, return a presigned upload URL
GET  /videos/{video_id}  -> return status; when ready, CDN playback URLs
"""

import json
import os
import uuid
from datetime import datetime, timezone

import boto3
from botocore.config import Config

RAW_BUCKET = os.environ["RAW_BUCKET"]
CDN_DOMAIN = os.environ["CDN_DOMAIN"]
UPLOAD_URL_TTL = int(os.environ["UPLOAD_URL_TTL"])
REGION = os.environ["AWS_REGION"]

# Presigned URLs must point at the regional endpoint: eu-south-2 is an
# opt-in region, unreachable through the global s3.amazonaws.com endpoint.
s3 = boto3.client(
    "s3",
    region_name=REGION,
    endpoint_url=f"https://s3.{REGION}.amazonaws.com",
    config=Config(signature_version="s3v4", s3={"addressing_style": "virtual"}),
)
table = boto3.resource("dynamodb").Table(os.environ["TABLE_NAME"])


def handler(event, context):
    route = event.get("routeKey")
    if route == "POST /videos":
        return create_video(event)
    if route == "GET /videos/{video_id}":
        return get_video(event)
    return respond(404, {"error": "route not found"})


def create_video(event):
    try:
        body = json.loads(event.get("body") or "{}")
    except json.JSONDecodeError:
        return respond(400, {"error": "request body must be valid JSON"})

    title = body.get("title")
    filename = body.get("filename")
    if not title or not filename:
        return respond(400, {"error": "'title' and 'filename' are required"})

    video_id = uuid.uuid4().hex
    raw_key = f"{video_id}/{os.path.basename(filename)}"

    table.put_item(
        Item={
            "video_id": video_id,
            "title": title,
            "raw_key": raw_key,
            "status": "uploading",
            "created_at": datetime.now(timezone.utc).isoformat(),
        }
    )

    upload_url = s3.generate_presigned_url(
        "put_object",
        Params={"Bucket": RAW_BUCKET, "Key": raw_key},
        ExpiresIn=UPLOAD_URL_TTL,
    )

    return respond(
        201,
        {
            "video_id": video_id,
            "upload_url": upload_url,
            "expires_in": UPLOAD_URL_TTL,
            "instructions": "PUT the video file to upload_url",
        },
    )


def get_video(event):
    video_id = event["pathParameters"]["video_id"]
    item = table.get_item(Key={"video_id": video_id}).get("Item")
    if not item:
        return respond(404, {"error": "video not found"})

    response = {
        "video_id": video_id,
        "title": item["title"],
        "status": item["status"],
    }
    if item["status"] == "ready":
        response["playback_urls"] = {
            rendition: f"https://{CDN_DOMAIN}/{video_id}/{rendition}.mp4"
            for rendition in item.get("renditions", [])
        }
    return respond(200, response)


def respond(status_code, body):
    return {
        "statusCode": status_code,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body),
    }
