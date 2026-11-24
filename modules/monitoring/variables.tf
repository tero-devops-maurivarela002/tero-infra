variable "name" {
  description = "Prefijo de los nombres (tero-<entorno>)."
  type        = string
}

variable "aws_region" {
  description = "Región de las métricas (para los widgets del dashboard)."
  type        = string
}

variable "cluster_name" {
  description = "Cluster ECS cuyos servicios se grafican (métricas de Container Insights)."
  type        = string
}

variable "service_names" {
  description = "Servicios ECS que se grafican (CPU, memoria y tareas corriendo)."
  type        = list(string)
}

variable "alb_arn_suffix" {
  description = "Sufijo del ARN del ALB público (dimensión LoadBalancer de AWS/ApplicationELB)."
  type        = string
}

variable "ui_target_group_arn_suffix" {
  description = "Sufijo del ARN del target group de ui (la tienda): base de la alarma de disponibilidad."
  type        = string
}

variable "alert_email" {
  description = "Email que recibe las alarmas por SNS. Vacío = sin suscripción (el topic igual se crea). Hay que confirmar el mail de AWS."
  type        = string
  default     = ""
}

variable "runbook_base_url" {
  description = "URL base de los runbooks; se agrega en la descripción de cada alarma."
  type        = string
}

variable "error_rate_threshold" {
  description = "Porcentaje de respuestas 5xx (sobre el total) que dispara la alarma de errores."
  type        = number
  default     = 5
}

variable "latency_p95_threshold_seconds" {
  description = "Latencia p95 del ALB (segundos) que dispara la alarma de rendimiento."
  type        = number
  default     = 1.5
}
