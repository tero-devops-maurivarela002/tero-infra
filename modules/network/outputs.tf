output "vpc_id" {
  description = "ID de la VPC."
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "Rango de IPs de la VPC."
  value       = aws_vpc.this.cidr_block
}

output "availability_zones" {
  description = "Zonas de disponibilidad usadas."
  value       = local.azs
}

output "public_subnet_ids" {
  description = "IDs de las subnets públicas (para el ALB)."
  value       = [for az in local.azs : aws_subnet.public[az].id]
}

output "private_subnet_ids" {
  description = "IDs de las subnets privadas (para ECS, RDS y ElastiCache)."
  value       = [for az in local.azs : aws_subnet.private[az].id]
}

output "nat_public_ips" {
  description = "IPs públicas de salida de los NAT Gateway (desde donde salen los servicios a internet)."
  value       = [for eip in aws_eip.nat : eip.public_ip]
}

output "alb_security_group_id" {
  description = "Security group del ALB."
  value       = aws_security_group.alb.id
}

output "services_security_group_id" {
  description = "Security group de las tareas de ECS."
  value       = aws_security_group.services.id
}

output "database_security_group_id" {
  description = "Security group de RDS (solo acepta desde los servicios)."
  value       = aws_security_group.database.id
}

output "redis_security_group_id" {
  description = "Security group de ElastiCache Redis (solo acepta desde los servicios)."
  value       = aws_security_group.redis.id
}
