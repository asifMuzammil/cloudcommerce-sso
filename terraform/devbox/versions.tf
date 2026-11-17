terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.region

  # Every resource gets these tags automatically -> easy cost tracking in Cost Explorer.
  default_tags {
    tags = {
      Project   = "cloudcommerce-sso"
      Component = "devbox"
      ManagedBy = "terraform"
    }
  }
}
