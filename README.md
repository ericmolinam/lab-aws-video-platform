# Video Streaming Platform Lab

A simple, fully deployable AWS implementation (Terraform) of the architecture described in the *Design a video streaming platform* document: internal teams upload video masters, a queue-driven pipeline "transcodes" them into multiple renditions, and members stream them through a CDN.

This stack lives in its own Terraform Cloud workspace (`lab-streaming`) and is completely independent from the EC2 lab in [`terraform/`](../terraform/).

---

## Architecture

```
                        upload flow
Internal teams ──► API Gateway ──► App Lambda ──► DynamoDB (metadata, status: uploading)
      │                                │
      │  presigned PUT URL ◄───────────┘
      ▼
S3 (raw masters) ──► S3 event ──► SQS (transcoding queue + DLQ)
                                        │
                                        ▼
                               Transcoder Lambda ──► S3 (encoded renditions)
                                        │
                                        └──► DynamoDB (status: ready + renditions)

                        streaming flow
Members ──► API Gateway ──► App Lambda ──► DynamoDB lookup
   │                            │
   │   playback URLs ◄──────────┘
   ▼
CloudFront (OAC) ──► S3 (encoded renditions, private)
```

Mapping to the design document (Figure 1):

| Design component | AWS implementation |
|---|---|
| API Gateway / Load balancer | API Gateway HTTP API |
| App server (`/upload`, `/watch`) | Lambda ([`lambda/app.py`](lambda/app.py)) |
| Metadata DB | DynamoDB (`videos` table) |
| Object storage (raw) | S3 bucket, private + encrypted |
| Transcoding queue | SQS + dead-letter queue |
| Video transcoders | Lambda ([`lambda/transcoder.py`](lambda/transcoder.py)) |
| Object storage (encoded) | S3 bucket, private + encrypted |
| CDN (signed access to encoded videos) | CloudFront with Origin Access Control |

---

## Simplifications vs. the design document

This is a lab, so a few production pieces are intentionally stubbed or omitted:

- **Transcoding is simulated.** The worker Lambda copies the master into the encoded bucket once per rendition (`1080p.mp4`, `720p.mp4`, ...) instead of actually re-encoding. The production path is AWS Elemental MediaConvert — which is not available in `eu-south-2` — submitted from the worker and completed via an EventBridge rule. The queue → worker → encoded bucket → metadata update flow is identical.
- **Single-part presigned uploads.** The design calls for multipart resumable uploads; here the app returns one presigned `PUT` URL. Swapping to `create_multipart_upload` + presigned part URLs is an app-level change only.
- **No CDN signed URLs / DRM / authentication.** CloudFront serves the (private) encoded bucket openly. Production would add a trusted key group so the app signs playback URLs, plus an IdP in front of the API.

---

## Deploy

### 1. Terraform Cloud workspace

Create a workspace named `lab-streaming` in the `emolinam5` organization and set the same OIDC environment variables used by the EC2 lab (`TFC_AWS_PROVIDER_AUTH=true`, `TFC_AWS_RUN_ROLE_ARN=...`). The IAM role needs permissions for: S3, SQS, DynamoDB, Lambda, IAM (roles/policies), API Gateway, and CloudFront.

> The GitHub Actions workflow only covers `terraform/**` (workspace `lab-ec2`), so this stack is deployed via CLI or TFC runs.

### 2. Apply

```bash
cd streaming
terraform login
terraform init
terraform apply
```

---

## Try the flow

```bash
API=$(terraform output -raw api_endpoint)

# 1. Register a video -> metadata row + presigned upload URL
RESPONSE=$(curl -s -X POST "$API/videos" \
  -H 'Content-Type: application/json' \
  -d '{"title": "Big Buck Bunny", "filename": "master.mp4"}')
echo "$RESPONSE" | jq

VIDEO_ID=$(echo "$RESPONSE" | jq -r .video_id)
UPLOAD_URL=$(echo "$RESPONSE" | jq -r .upload_url)

# 2. Upload the master straight to S3 (bypasses the app server)
curl -X PUT --upload-file ./eric-molina-video.mp4 "$UPLOAD_URL"

# 3. Poll until the pipeline marks it ready, then grab the playback URLs
curl -s "$API/videos/$VIDEO_ID" | jq
```

When the status is `ready`, the response includes one CloudFront URL per rendition:

```json
{
  "video_id": "3f2a...",
  "title": "Big Buck Bunny",
  "status": "ready",
  "playback_urls": {
    "1080p": "https://dxxxx.cloudfront.net/3f2a.../1080p.mp4",
    "720p":  "https://dxxxx.cloudfront.net/3f2a.../720p.mp4",
    "480p":  "https://dxxxx.cloudfront.net/3f2a.../480p.mp4"
  }
}
```

---

## Variables

| Name | Description | Default |
|---|---|---|
| `aws_region` | AWS region to deploy resources | `eu-south-2` |
| `project` | Prefix used to name all resources | `streaming-lab` |
| `renditions` | Qualities produced per uploaded master | `["1080p", "720p", "480p"]` |
| `upload_url_ttl` | Presigned upload URL expiration (seconds) | `3600` |

## Outputs

| Name | Description |
|---|---|
| `api_endpoint` | Base URL of the app server API |
| `cdn_domain` | CloudFront domain serving the encoded videos |
| `raw_bucket` | Bucket receiving master uploads |
| `encoded_bucket` | Bucket holding transcoded renditions |

---

## Project structure

```
streaming/
├── backend.tf        # Terraform Cloud workspace + providers
├── variables.tf      # Input variables
├── storage.tf        # Raw + encoded S3 buckets, upload notification
├── queue.tf          # Transcoding SQS queue + DLQ
├── database.tf       # DynamoDB video metadata table
├── app.tf            # App Lambda + API Gateway (upload/watch endpoints)
├── transcoder.tf     # Worker Lambda + SQS event source mapping
├── cdn.tf            # CloudFront distribution + OAC bucket policy
├── outputs.tf        # API endpoint, CDN domain, bucket names
└── lambda/
    ├── app.py        # App server: presigned URLs + metadata lookups
    └── transcoder.py # Transcoding worker (stub renditions)
```
