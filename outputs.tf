output "account_id" {
  description = "ID de la cuenta de AWS donde se aplicó este ambiente (sirve para confirmar que estamos en el lab correcto)."
  value       = data.aws_caller_identity.current.account_id
}

output "region" {
  description = "Región de AWS usada por el provider."
  value       = data.aws_region.current.region
}

output "environment" {
  description = "Ambiente al que corresponde este state (dev, test o prod)."
  value       = var.environment
}

output "vpc_id" {
  description = "ID de la VPC del ambiente."
  value       = module.network.vpc_id
}

output "public_subnet_ids" {
  description = "Subnets públicas (ALB y NAT)."
  value       = module.network.public_subnet_ids
}

output "private_subnet_ids" {
  description = "Subnets privadas (ECS, RDS y Redis)."
  value       = module.network.private_subnet_ids
}

output "nat_public_ips" {
  description = "IPs públicas por las que salen a internet los servicios."
  value       = module.network.nat_public_ips
}

output "alb_url" {
  description = "URL pública de la tienda (ui)."
  value       = "http://${module.alb.dns_name}"
}

output "admin_url" {
  description = "URL del panel de administración (solo desde admin_allowed_cidrs)."
  value       = "http://${module.alb.dns_name}:8081"
}

output "ecs_cluster_name" {
  description = "Nombre del cluster ECS (lo usa el CD para update-service)."
  value       = aws_ecs_cluster.this.name
}

output "ecs_services" {
  description = "Servicios ECS por nombre, con su familia de task definition y log group."
  value = { for k, s in module.service : k => {
    service         = s.service_name
    task_definition = s.task_definition_family
    log_group       = s.log_group_name
  } }
}

output "ecr_registry" {
  description = "Registry de ECR de la cuenta, de donde salen las imágenes."
  value       = local.ecr_registry
}

output "db_endpoint" {
  description = "Host y puerto de PostgreSQL (solo accesible desde los servicios)."
  value       = "${module.database.db_address}:${module.database.db_port}"
}

output "db_secret_arn" {
  description = "ARN del secreto con las credenciales de la base."
  value       = module.database.db_secret_arn
}

output "admin_secret_arn" {
  description = "ARN del secreto con las credenciales del panel de administración."
  value       = aws_secretsmanager_secret.admin.arn
}

output "redis_endpoint" {
  description = "Host de Redis (solo accesible desde los servicios)."
  value       = module.database.redis_endpoint
}

output "db_init_task_definition" {
  description = "Familia de la tarea que inicializa la base (ver scripts/inicializar-db.sh)."
  value       = aws_ecs_task_definition.db_init.family
}

output "services_security_group_id" {
  description = "Security group de las tareas (lo usa scripts/inicializar-db.sh)."
  value       = module.network.services_security_group_id
}
