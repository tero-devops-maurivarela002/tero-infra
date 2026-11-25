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

variable "alert_email" {
  description = "Email que recibe las alertas del escaneo de ECR (secret ALERT_EMAIL). Vacío = sin suscripción."
  type        = string
  default     = ""
  sensitive   = true
}

variable "scan_alert_severities" {
  description = "Severidades del escaneo de ECR que generan un aviso (DEVOPS-46)."
  type        = list(string)
  default     = ["CRITICAL", "HIGH"]

  validation {
    condition     = alltrue([for s in var.scan_alert_severities : contains(["CRITICAL", "HIGH", "MEDIUM", "LOW", "INFORMATIONAL", "UNDEFINED"], s)])
    error_message = "Severidades válidas: CRITICAL, HIGH, MEDIUM, LOW, INFORMATIONAL, UNDEFINED."
  }
}
