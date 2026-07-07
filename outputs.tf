output "api_endpoint" {
  description = "Base URL of the app server API (POST /videos, GET /videos/{video_id})."
  value       = aws_apigatewayv2_api.this.api_endpoint
}

output "cdn_domain" {
  description = "CloudFront domain that serves the encoded videos."
  value       = aws_cloudfront_distribution.this.domain_name
}

output "raw_bucket" {
  description = "Bucket receiving the master uploads."
  value       = aws_s3_bucket.raw.id
}

output "encoded_bucket" {
  description = "Bucket holding the transcoded renditions."
  value       = aws_s3_bucket.encoded.id
}
