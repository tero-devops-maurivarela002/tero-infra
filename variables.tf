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

variable "vpc_cidr" {
  description = "Rango de IPs de la VPC del ambiente. Uno distinto por ambiente para poder conectarlas en el futuro sin solaparse."
  type        = string
}

variable "az_count" {
  description = "Cantidad de zonas de disponibilidad (2 alcanza para el ALB y Multi-AZ)."
  type        = number
  default     = 2
}

variable "single_nat_gateway" {
  description = "true: un NAT compartido (barato, dev y test). false: un NAT por zona (alta disponibilidad, prod)."
  type        = bool
  default     = true
}
