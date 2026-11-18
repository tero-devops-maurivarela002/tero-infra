terraform {
  # use_lockfile (lock en S3) necesita >= 1.10 y los atributos write-only (secretos fuera del state) >= 1.11.
  required_version = ">= 1.11.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
  }

  # Configuración parcial: los valores salen de backend/<entorno>.hcl
  # y el nombre del bucket se pasa en el init (ver README).
  backend "s3" {}
}
