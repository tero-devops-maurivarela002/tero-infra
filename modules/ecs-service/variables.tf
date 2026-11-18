variable "name" {
  description = "Nombre del servicio (catalog, carts, orders, checkout, ui o admin)."
  type        = string
}

variable "name_prefix" {
  description = "Prefijo del ambiente, por ejemplo tero-dev."
  type        = string
}

variable "environment" {
  description = "Ambiente (dev, test o prod), para el nombre del log group."
  type        = string
}

variable "cluster_arn" {
  description = "ARN del cluster ECS donde corre el servicio."
  type        = string
}

variable "image" {
  description = "Imagen completa con tag, por ejemplo <cuenta>.dkr.ecr.us-east-1.amazonaws.com/tero/catalog:<sha>."
  type        = string
}

variable "cpu" {
  description = "CPU de la tarea en unidades de Fargate (256 = 0,25 vCPU)."
  type        = number
  default     = 256
}

variable "memory" {
  description = "Memoria de la tarea en MiB."
  type        = number
  default     = 512
}

variable "container_port" {
  description = "Puerto en el que escucha el contenedor."
  type        = number
  default     = 8080
}

variable "desired_count" {
  description = "Cantidad de tareas que el servicio mantiene corriendo."
  type        = number
  default     = 1
}

variable "environment_variables" {
  description = "Variables de entorno sin secretos (nombre => valor)."
  type        = map(string)
  default     = {}
}

variable "secrets" {
  description = "Variables de entorno que salen de Secrets Manager (nombre => ARN o ARN:clave-json::). No quedan en la task definition en texto plano."
  type        = map(string)
  default     = {}
}

variable "subnet_ids" {
  description = "Subnets privadas donde corren las tareas."
  type        = list(string)
}

variable "security_group_ids" {
  description = "Security groups de las tareas."
  type        = list(string)
}

variable "execution_role_arn" {
  description = "Rol con el que ECS baja la imagen, lee secretos y escribe logs (en Academy, LabRole)."
  type        = string
}

variable "task_role_arn" {
  description = "Rol que usa el código del contenedor para llamar a AWS (en Academy, LabRole)."
  type        = string
}

variable "target_group_arn" {
  description = "Target group del ALB (público o interno) al que se registra el servicio. null si no recibe tráfico."
  type        = string
  default     = null
}

variable "log_retention_days" {
  description = "Días que se guardan los logs en CloudWatch."
  type        = number
  default     = 7
}

variable "health_check_grace_period" {
  description = "Segundos que el ALB espera antes de evaluar la salud de una tarea nueva."
  type        = number
  default     = 60
}
