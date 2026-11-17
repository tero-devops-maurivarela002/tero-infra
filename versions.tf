terraform {
  # use_lockfile (lock nativo en S3, sin DynamoDB) necesita Terraform >= 1.10.
  required_version = ">= 1.10.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # Configuración parcial: los valores salen de backend/<entorno>.hcl
  # y el nombre del bucket se pasa en el init (ver README).
  backend "s3" {}
}
