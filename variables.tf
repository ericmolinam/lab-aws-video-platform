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