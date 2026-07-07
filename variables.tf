variable "aws_region" {
  description = "AWS region where resources will be deployed."
  type        = string
  default     = "eu-south-2"
}

variable "project" {
  description = "Prefix used to name all resources of the streaming platform."
  type        = string
  default     = "video-platform"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,30}$", var.project))
    error_message = "The project variable must be lowercase alphanumeric/hyphens, 3-31 chars, starting with a letter."
  }
}

variable "upload_url_ttl" {
  description = "Expiration time (in seconds) of the presigned upload URLs returned by the app."
  type        = number
  default     = 3600

  validation {
    condition     = var.upload_url_ttl >= 60 && var.upload_url_ttl <= 604800
    error_message = "The upload_url_ttl variable must be between 60 seconds and 7 days."
  }
}

variable "renditions" {
  description = "Video qualities the transcoding step produces for each uploaded master."
  type        = list(string)
  default     = ["1080p", "720p", "480p"]

  validation {
    condition     = length(var.renditions) > 0
    error_message = "The renditions variable must contain at least one quality."
  }
}