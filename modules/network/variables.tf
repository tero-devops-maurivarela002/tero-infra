variable "name" {
  description = "Prefijo para los nombres de los recursos, por ejemplo tero-dev."
  type        = string
}

variable "vpc_cidr" {
  description = "Rango de IPs de la VPC (un /16, por ejemplo 10.10.0.0/16)."
  type        = string

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0)) && tonumber(split("/", var.vpc_cidr)[1]) <= 20
    error_message = "vpc_cidr tiene que ser un CIDR válido de /20 o más grande (se recomienda /16)."
  }
}

variable "az_count" {
  description = "Cantidad de zonas de disponibilidad a usar (mínimo 2, lo pide el ALB)."
  type        = number
  default     = 2

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 3
    error_message = "az_count tiene que ser 2 o 3."
  }
}

variable "single_nat_gateway" {
  description = "true: un solo NAT Gateway compartido (más barato, para dev y test). false: un NAT por zona (si se cae una zona, las otras siguen saliendo a internet; para prod)."
  type        = bool
  default     = true
}

variable "app_port" {
  description = "Puerto en el que escuchan los contenedores de Tero (todos usan 8080)."
  type        = number
  default     = 8080
}

variable "postgres_port" {
  description = "Puerto de PostgreSQL (RDS)."
  type        = number
  default     = 5432
}

variable "redis_port" {
  description = "Puerto de Redis (ElastiCache)."
  type        = number
  default     = 6379
}
