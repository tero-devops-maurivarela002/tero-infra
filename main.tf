data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

locals {
  name         = "tero-${var.environment}"
  ecr_registry = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.region}.amazonaws.com"

  # Puertos del ALB interno: uno por servicio de backend.
  internal_ports = {
    catalog  = 8001
    carts    = 8002
    orders   = 8003
    checkout = 8004
  }
}

# Red: VPC, subnets públicas y privadas en 2 zonas, NAT y security groups.
module "network" {
  source = "./modules/network"

  name                = local.name
  vpc_cidr            = var.vpc_cidr
  az_count            = var.az_count
  single_nat_gateway  = var.single_nat_gateway
  admin_allowed_cidrs = var.admin_allowed_cidrs
  internal_alb_ports  = values(local.internal_ports)
}

# ALB público: :80 -> ui, :8081 -> admin.
module "alb" {
  source = "./modules/alb"

  name                = local.name
  vpc_id              = module.network.vpc_id
  subnet_ids          = module.network.public_subnet_ids
  security_group_id   = module.network.alb_security_group_id
  listeners           = { ui = 80, admin = 8081 }
  deletion_protection = var.alb_deletion_protection
}

# ALB interno: así se llaman los servicios entre sí (en Academy no hay Cloud Map).
module "internal_alb" {
  source = "./modules/alb"

  name                = "${local.name}-int"
  internal            = true
  vpc_id              = module.network.vpc_id
  subnet_ids          = module.network.private_subnet_ids
  security_group_id   = module.network.internal_alb_security_group_id
  listeners           = local.internal_ports
  deletion_protection = var.alb_deletion_protection
}

# PostgreSQL (RDS) y Redis (ElastiCache) en subnets privadas.
module "database" {
  source = "./modules/database"

  name                       = local.name
  private_subnet_ids         = module.network.private_subnet_ids
  database_security_group_id = module.network.database_security_group_id
  redis_security_group_id    = module.network.redis_security_group_id

  db_engine_version        = var.db_engine_version
  db_instance_class        = var.db_instance_class
  db_multi_az              = var.db_multi_az
  db_backup_retention_days = var.db_backup_retention_days
  db_deletion_protection   = var.db_deletion_protection
  db_skip_final_snapshot   = var.db_skip_final_snapshot
  db_password_version      = var.db_password_version
  redis_node_type          = var.redis_node_type
  redis_replicas           = var.redis_replicas
}
