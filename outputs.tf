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
