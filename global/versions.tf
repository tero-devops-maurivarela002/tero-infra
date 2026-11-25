terraform {
  required_version = ">= 1.11.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    # Arma el .zip de la Lambda de seguridad (DEVOPS-46).
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.7"
    }
  }

  # Mismo bucket que los ambientes, key global/terraform.tfstate (backend/global.hcl).
  backend "s3" {}
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "tero"
      Environment = "global"
      ManagedBy   = "terraform"
      Repository  = "tero-infra"
    }
  }
}
