variable "name" {
  description = "Prefijo de los nombres, por ejemplo tero-dev."
  type        = string
}

variable "vpc_id" {
  description = "VPC donde se crean los target groups."
  type        = string
}

variable "public_subnet_ids" {
  description = "Subnets públicas donde vive el ALB (al menos 2 zonas)."
  type        = list(string)
}

variable "security_group_id" {
  description = "Security group del ALB (sale del módulo network)."
  type        = string
}

variable "app_port" {
  description = "Puerto de los contenedores detrás del ALB."
  type        = number
  default     = 8080
}

variable "admin_listener_port" {
  description = "Puerto del listener del panel de administración."
  type        = number
  default     = 8081
}

variable "health_check_path" {
  description = "Ruta que el ALB consulta para saber si una tarea está sana."
  type        = string
  default     = "/health"
}

variable "deletion_protection" {
  description = "Si es true, el ALB no se puede borrar sin desactivarla antes (para prod)."
  type        = bool
  default     = false
}
