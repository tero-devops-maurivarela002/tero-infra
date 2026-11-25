provider "aws" {
  region = var.aws_region

  # Todas las cosas que cree Terraform quedan etiquetadas igual,
  # así se pueden filtrar por proyecto y ambiente en la consola y en costos.
  default_tags {
    tags = {
      Project     = "tero"
      Environment = var.environment
      ManagedBy   = "terraform"
      Repository  = "tero-infra"
    }
  }
}
