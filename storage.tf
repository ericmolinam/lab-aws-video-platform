resource "aws_s3_bucket" "raw" {
  bucket_prefix = "${var.project}-raw-"

  tags = {
    Name = "raw-videos"
  }
}

resource "aws_s3_bucket" "encoded" {
  bucket_prefix = "${var.project}-encoded-"

  tags = {
    Name = "encoded-videos"
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  for_each = {
    raw     = aws_s3_bucket.raw.id
    encoded = aws_s3_bucket.encoded.id
  }
  bucket = each.value

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}


resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  for_each = {
    raw     = aws_s3_bucket.raw.id
    encoded = aws_s3_bucket.encoded.id
  }
  bucket = each.value

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Browsers upload straight to the raw bucket with the presigned URL,
# so the bucket must accept cross-origin PUTs.
resource "aws_s3_bucket_cors_configuration" "raw" {
  bucket = aws_s3_bucket.raw.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["PUT"]
    allowed_origins = ["*"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3600
  }
}

# Upload finished -> enqueue a transcoding job.
resource "aws_s3_bucket_notification" "raw" {
  bucket = aws_s3_bucket.raw.id

  queue {
    queue_arn = aws_sqs_queue.this.arn
    events    = ["s3:ObjectCreated:*"]
  }

  depends_on = [aws_sqs_queue_policy.this]
}
