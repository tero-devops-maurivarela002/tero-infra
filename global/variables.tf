variable "aws_region" {
  description = "Región de AWS. En AWS Academy es us-east-1."
  type        = string
  default     = "us-east-1"
}

variable "repository_prefix" {
  description = "Prefijo de los repositorios de ECR: quedan como <prefijo>/<servicio>."
  type        = string
  default     = "tero"
}

variable "services" {
  description = "Servicios de tero-app que tienen imagen (nombre de la carpeta en src/)."
  type        = set(string)
  default     = ["catalog", "cart", "orders", "checkout", "ui", "admin"]
}

variable "images_to_keep" {
  description = "Cantidad de imágenes que se guardan por repositorio; las más viejas se borran solas."
  type        = number
  default     = 30
}
