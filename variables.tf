variable "aws_region" {
  description = "Región de AWS donde se despliega Tero. En AWS Academy es us-east-1."
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Nombre del ambiente: dev, test o prod. Se usa en nombres y etiquetas."
  type        = string

  validation {
    condition     = contains(["dev", "test", "prod"], var.environment)
    error_message = "environment tiene que ser dev, test o prod."
  }
}
