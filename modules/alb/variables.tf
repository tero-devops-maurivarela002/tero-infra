variable "name" {
  description = "Prefijo de los nombres, por ejemplo tero-dev."
  type        = string
}

variable "vpc_id" {
  description = "VPC donde se crean los target groups."
  type        = string
}

variable "internal" {
  description = "false: ALB público (subnets públicas). true: ALB interno, solo accesible dentro de la VPC."
  type        = bool
  default     = false
}

variable "listeners" {
  description = "Un listener HTTP y un target group por entrada: nombre => puerto del ALB."
  type        = map(number)
}

variable "subnet_ids" {
  description = "Subnets donde vive el ALB: públicas si es público, privadas si es interno (al menos 2 zonas)."
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
