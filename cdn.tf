resource "aws_cloudfront_origin_access_control" "encoded" {
  name                              = "${var.project}-encoded"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "this" {
  enabled = true
  comment = "${var.project} video delivery"

  price_class = "PriceClass_100"

  origin {
    origin_id                = "encoded-videos"
    domain_name              = aws_s3_bucket.encoded.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.encoded.id
  }

  default_cache_behavior {
    target_origin_id       = "encoded-videos"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    viewer_protocol_policy = "redirect-to-https"
    compress               = false # video is already compressed

    cache_policy_id = "658327ea-f89d-4fab-a63d-7e88639e58f6"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

resource "aws_s3_bucket_policy" "encoded" {
  bucket = aws_s3_bucket.encoded.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowCloudFrontRead"
        Effect    = "Allow"
        Principal = { Service = "cloudfront.amazonaws.com" }
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.encoded.arn}/*"
        Condition = {
          StringEquals = { "AWS:SourceArn" = aws_cloudfront_distribution.this.arn }
        }
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.this]
}
