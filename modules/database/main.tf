# Base de datos (RDS PostgreSQL) y Redis (ElastiCache) de Tero (DEVOPS-43).
#
# Los dos viven en subnets privadas y sus security groups solo aceptan
# tráfico desde los servicios (observación C del assessment).
#
# Contraseña: se genera con un recurso *ephemeral* y se pasa con atributos
# *write-only* (password_wo, secret_string_wo). Terraform la manda a AWS pero
# NO la guarda en el state ni en el plan. Las tareas de ECS la leen de
# Secrets Manager.

# ---------------------------------------------------------------- Secreto

ephemeral "random_password" "db" {
  length  = 32
  special = false # evita problemas de escape en URLs y DSN
}

resource "aws_secretsmanager_secret" "db" {
  #checkov:skip=CKV2_AWS_57:La rotación automática requiere una Lambda con rol propio (Academy no permite crear roles); rotación manual en el runbook (DEVOPS-35)
  #checkov:skip=CKV_AWS_149:Cifrado con la clave administrada por AWS (aws/secretsmanager); una CMK suma costo y gestión de key policies

  name        = "${var.name}/database"
  description = "Credenciales de PostgreSQL de ${var.name} (usuario, contraseña, host, puerto)."

  # En dev/test se puede borrar y recrear enseguida (default: 30 días de espera).
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id

  secret_string_wo = jsonencode({
    username = var.db_username
    password = ephemeral.random_password.db.result
    host     = aws_db_instance.this.address
    port     = aws_db_instance.this.port
  })
  secret_string_wo_version = var.db_password_version
}

# ---------------------------------------------------------------- PostgreSQL

resource "aws_db_subnet_group" "this" {
  name       = "${var.name}-db"
  subnet_ids = var.private_subnet_ids
  tags       = { Name = "${var.name}-db" }
}

resource "aws_db_parameter_group" "this" {
  name   = "${var.name}-postgres${var.db_engine_version}"
  family = "postgres${var.db_engine_version}"

  parameter {
    name  = "rds.force_ssl"
    value = var.db_force_ssl ? "1" : "0"
  }

  # Registrar las consultas que tarden más de 1 s (útil para diagnosticar).
  parameter {
    name  = "log_min_duration_statement"
    value = "1000"
  }
}

resource "aws_db_instance" "this" {
  #checkov:skip=CKV_AWS_157:Multi-AZ es por ambiente (db_multi_az: true en prod)
  #checkov:skip=CKV_AWS_293:Deletion protection es por ambiente (db_deletion_protection: true en prod)
  #checkov:skip=CKV_AWS_118:Enhanced monitoring requiere un rol de IAM propio (no permitido en Academy); se usan métricas de CloudWatch
  #checkov:skip=CKV_AWS_161:Las apps se autentican con usuario/contraseña desde Secrets Manager; IAM auth requiere cambios en las apps
  #checkov:skip=CKV_AWS_353:Performance Insights no se usa en db.t3.micro de dev/test; evaluar en prod
  #checkov:skip=CKV2_AWS_69:catalog y orders usan sslmode=disable; forzar TLS (rds.force_ssl=1) queda como hallazgo abierto para DEVOPS-37

  identifier     = "${var.name}-postgres"
  engine         = "postgres"
  engine_version = var.db_engine_version
  instance_class = var.db_instance_class

  allocated_storage = var.db_allocated_storage
  storage_type      = "gp3"
  storage_encrypted = true

  db_name             = var.db_initial_name
  username            = var.db_username
  password_wo         = ephemeral.random_password.db.result
  password_wo_version = var.db_password_version

  db_subnet_group_name   = aws_db_subnet_group.this.name
  parameter_group_name   = aws_db_parameter_group.this.name
  vpc_security_group_ids = [var.database_security_group_id]
  publicly_accessible    = false
  multi_az               = var.db_multi_az

  backup_retention_period    = var.db_backup_retention_days
  auto_minor_version_upgrade = true
  copy_tags_to_snapshot      = true
  deletion_protection        = var.db_deletion_protection
  skip_final_snapshot        = var.db_skip_final_snapshot
  final_snapshot_identifier  = var.db_skip_final_snapshot ? null : "${var.name}-postgres-final"

  enabled_cloudwatch_logs_exports = ["postgresql"]

  # Los cambios (por ejemplo, de contraseña) se aplican enseguida y no en la
  # ventana de mantenimiento: lo necesitamos para la rotación.
  apply_immediately = true

  tags = { Name = "${var.name}-postgres" }
}

# ---------------------------------------------------------------- Redis

resource "aws_elasticache_subnet_group" "this" {
  name       = "${var.name}-redis"
  subnet_ids = var.private_subnet_ids
}

resource "aws_elasticache_replication_group" "this" {
  #checkov:skip=CKV_AWS_31:TLS en tránsito está activo; AUTH token pendiente (requiere cambiar la URL de checkout). Acceso solo desde el SG de servicios
  #checkov:skip=CKV_AWS_191:Cifrado en reposo con la clave administrada por AWS; una CMK suma costo y gestión de key policies
  #checkov:skip=CKV2_AWS_50:Multi-AZ con failover es por ambiente (redis_replicas: 1 en prod)

  replication_group_id = "${var.name}-redis"
  description          = "Redis de ${var.name} (carritos en checkout)"

  engine             = "redis"
  engine_version     = var.redis_engine_version
  node_type          = var.redis_node_type
  num_cache_clusters = 1 + var.redis_replicas
  port               = 6379

  subnet_group_name  = aws_elasticache_subnet_group.this.name
  security_group_ids = [var.redis_security_group_id]

  automatic_failover_enabled = var.redis_replicas > 0
  multi_az_enabled           = var.redis_replicas > 0

  # Cifrado en reposo y en tránsito: checkout se conecta con rediss:// (TLS).
  at_rest_encryption_enabled = true
  transit_encryption_enabled = true

  apply_immediately = true

  tags = { Name = "${var.name}-redis" }
}
