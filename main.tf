data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

locals {
  name = "tero-${var.environment}"
}

# Red: VPC, subnets públicas y privadas en 2 zonas, NAT y security groups.
module "network" {
  source = "./modules/network"

  name               = local.name
  vpc_cidr           = var.vpc_cidr
  az_count           = var.az_count
  single_nat_gateway = var.single_nat_gateway
}
