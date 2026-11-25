variable "name" {
  description = "Prefijo de los nombres, por ejemplo tero-dev."
  type        = string
}

variable "private_subnet_ids" {
  description = "Subnets privadas donde viven RDS y Redis."
  type        = list(string)
}

variable "database_security_group_id" {
  description = "Security group de RDS (sale del módulo network)."
  type        = string
}

variable "redis_security_group_id" {
  description = "Security group de Redis (sale del módulo network)."
  type        = string
}

# ---------------------------------------------------------------- PostgreSQL

variable "db_engine_version" {
  description = "Versión mayor de PostgreSQL (la misma que usa docker-compose)."
  type        = string
  default     = "16"
}

variable "db_instance_class" {
  description = "Tamaño de la instancia RDS."
  type        = string
  default     = "db.t3.micro"
}

variable "db_allocated_storage" {
  description = "Disco de RDS en GB."
  type        = number
  default     = 20
}

variable "db_username" {
  description = "Usuario maestro de PostgreSQL. Es el mismo que usa init-db.sql en tero-app."
  type        = string
  default     = "retail_user"
}

variable "db_initial_name" {
  description = "Base que RDS crea al arrancar (las otras las crea la tarea db-init)."
  type        = string
  default     = "orders"
}

variable "db_multi_az" {
  description = "true: réplica en espera en otra zona con failover automático (prod)."
  type        = bool
  default     = false
}

variable "db_backup_retention_days" {
  description = "Días de backups automáticos de RDS (0 los desactiva)."
  type        = number
  default     = 1
}

variable "db_deletion_protection" {
  description = "Si es true, RDS no se puede borrar sin desactivarla antes."
  type        = bool
  default     = false
}

variable "db_skip_final_snapshot" {
  description = "Si es true, al destruir RDS no se saca un snapshot final (dev y test)."
  type        = bool
  default     = true
}

variable "db_force_ssl" {
  description = "Si es true, RDS rechaza conexiones sin TLS. Hoy catalog y orders conectan con sslmode=disable (ver README)."
  type        = bool
  default     = false
}

variable "db_password_version" {
  description = "Versión de la contraseña de la base. Subirla en 1 genera una contraseña nueva y la cambia en RDS y en Secrets Manager (rotación)."
  type        = number
  default     = 1
}

# ---------------------------------------------------------------- Redis

variable "redis_engine_version" {
  description = "Versión de Redis OSS en ElastiCache."
  type        = string
  default     = "7.1"
}

variable "redis_node_type" {
  description = "Tamaño del nodo de ElastiCache."
  type        = string
  default     = "cache.t3.micro"
}

variable "redis_replicas" {
  description = "Réplicas de Redis además del primario (0 en dev; 1 en prod habilita failover)."
  type        = number
  default     = 0
}
