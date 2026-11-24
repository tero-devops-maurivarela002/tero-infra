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

variable "admin_allowed_cidrs" {
  description = "IPs (en formato CIDR, por ejemplo 1.2.3.4/32) que pueden entrar al panel de administración en el puerto 8081 del ALB."
  type        = list(string)
  default     = []
}

variable "alb_deletion_protection" {
  description = "Protege el ALB contra borrados (prod)."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------- ECS

variable "ecr_repository_prefix" {
  description = "Prefijo de los repositorios de ECR: las imágenes son <registry>/<prefijo>/<servicio>."
  type        = string
  default     = "tero"
}

variable "image_tag" {
  description = "Tag de las imágenes a desplegar (el SHA del commit de tero-app)."
  type        = string
}

variable "service_desired_count" {
  description = "Tareas por servicio (1 en dev, 2 en prod para alta disponibilidad)."
  type        = number
  default     = 1
}

variable "service_cpu" {
  description = "CPU por tarea en unidades de Fargate (256 = 0,25 vCPU)."
  type        = number
  default     = 256
}

variable "service_memory" {
  description = "Memoria por tarea en MiB."
  type        = number
  default     = 512
}

variable "log_retention_days" {
  description = "Días de retención de los logs en CloudWatch (7 en dev, 14 en prod)."
  type        = number
  default     = 7
}

variable "admin_username" {
  description = "Usuario del panel de administración (la contraseña la genera Terraform y queda en Secrets Manager)."
  type        = string
  default     = "admin"
}

variable "admin_secret_version" {
  description = "Subirla en 1 regenera la contraseña del admin y la clave JWT (rotación)."
  type        = number
  default     = 1
}

# ---------------------------------------------------------------- Base de datos y Redis

variable "db_engine_version" {
  description = "Versión mayor de PostgreSQL."
  type        = string
  default     = "16"
}

variable "db_instance_class" {
  description = "Tamaño de la instancia RDS."
  type        = string
  default     = "db.t3.micro"
}

variable "db_multi_az" {
  description = "RDS con réplica en espera en otra zona (prod)."
  type        = bool
  default     = false
}

variable "db_backup_retention_days" {
  description = "Días de backups automáticos de RDS."
  type        = number
  default     = 1
}

variable "db_deletion_protection" {
  description = "Protege RDS contra borrados (prod)."
  type        = bool
  default     = false
}

variable "db_skip_final_snapshot" {
  description = "No sacar snapshot final al destruir RDS (dev y test)."
  type        = bool
  default     = true
}

variable "db_password_version" {
  description = "Subirla en 1 genera una contraseña nueva para la base (rotación)."
  type        = number
  default     = 1
}

variable "redis_node_type" {
  description = "Tamaño del nodo de Redis."
  type        = string
  default     = "cache.t3.micro"
}

variable "redis_replicas" {
  description = "Réplicas de Redis además del primario."
  type        = number
  default     = 0
}

variable "alert_email" {
  description = "Email que recibe las alarmas (SNS). No se versiona (repo público): el pipeline lo toma del secret ALERT_EMAIL. Vacío = sin suscripción."
  type        = string
  default     = ""
  sensitive   = true
}
