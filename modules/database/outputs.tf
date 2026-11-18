output "db_address" {
  description = "Host de PostgreSQL (solo resuelve dentro de la VPC)."
  value       = aws_db_instance.this.address
}

output "db_port" {
  description = "Puerto de PostgreSQL."
  value       = aws_db_instance.this.port
}

output "db_username" {
  description = "Usuario maestro de PostgreSQL."
  value       = aws_db_instance.this.username
}

output "db_instance_id" {
  description = "Identificador de la instancia RDS (para métricas y alarmas)."
  value       = aws_db_instance.this.identifier
}

output "db_secret_arn" {
  description = "ARN del secreto de Secrets Manager con las credenciales de la base (las tareas lo leen con valueFrom)."
  value       = aws_secretsmanager_secret.db.arn
}

output "redis_endpoint" {
  description = "Host del nodo primario de Redis."
  value       = aws_elasticache_replication_group.this.primary_endpoint_address
}

output "redis_url" {
  description = "URL de conexión a Redis con TLS (rediss://), para checkout."
  value       = "rediss://${aws_elasticache_replication_group.this.primary_endpoint_address}:6379"
}
