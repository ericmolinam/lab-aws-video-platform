terraform {
  required_version = ">= 1.15"

  cloud {
    organization = "emolinam5"
    workspaces {
      name = "lab-video-platform"
    }
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}
