# Módulo de red de Tero (DEVOPS-42).
#
# Arma una VPC con dos tipos de subnet en cada zona de disponibilidad:
#   - públicas: tienen ruta al Internet Gateway. Acá vive solo el ALB y los NAT.
#   - privadas: sin ruta de entrada desde internet. Acá corren los servicios de
#     ECS, la base de datos (RDS) y Redis. Salen a internet (por ejemplo, para
#     bajar imágenes de ECR) a través del NAT Gateway.

data "aws_region" "current" {}

# Se fijan las zonas por nombre (a, b, c) en vez de tomar "las que haya": si AWS
# agrega una zona nueva, la red no cambia sola (Checkov CKV_AWS_394).
data "aws_availability_zones" "available" {
  state = "available"

  filter {
    name   = "zone-name"
    values = [for s in ["a", "b", "c"] : "${data.aws_region.current.region}${s}"]
  }
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, var.az_count)

  # Con un /16: públicas 10.x.0.0/24, 10.x.1.0/24 ... y privadas 10.x.10.0/24, 10.x.11.0/24 ...
  newbits = 24 - tonumber(split("/", var.vpc_cidr)[1])

  public_subnets  = { for i, az in local.azs : az => cidrsubnet(var.vpc_cidr, local.newbits, i) }
  private_subnets = { for i, az in local.azs : az => cidrsubnet(var.vpc_cidr, local.newbits, i + 10) }

  # Zonas que llevan NAT: solo la primera, o todas.
  nat_azs = var.single_nat_gateway ? [local.azs[0]] : local.azs
}

# ---------------------------------------------------------------- VPC

resource "aws_vpc" "this" {
  #checkov:skip=CKV2_AWS_11:Flow logs a CloudWatch requieren un rol propio (no permitido en Academy); mejora planificada con destino S3

  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true # necesario para los endpoints y para RDS/ElastiCache

  tags = { Name = "${var.name}-vpc" }
}

# El security group "default" de la VPC queda sin reglas: nadie lo usa por error.
resource "aws_default_security_group" "this" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name}-default-sin-reglas" }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name}-igw" }
}

# ---------------------------------------------------------------- Subnets públicas

resource "aws_subnet" "public" {
  for_each = local.public_subnets

  vpc_id            = aws_vpc.this.id
  availability_zone = each.key
  cidr_block        = each.value

  # No se asigna IP pública automáticamente: el ALB y los NAT tienen las suyas.
  map_public_ip_on_launch = false

  tags = { Name = "${var.name}-public-${each.key}", Tier = "public" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name}-public" }
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

# ---------------------------------------------------------------- NAT

resource "aws_eip" "nat" {
  for_each = toset(local.nat_azs)

  domain = "vpc"
  tags   = { Name = "${var.name}-nat-${each.key}" }

  depends_on = [aws_internet_gateway.this]
}

resource "aws_nat_gateway" "this" {
  for_each = toset(local.nat_azs)

  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = aws_subnet.public[each.key].id
  tags          = { Name = "${var.name}-nat-${each.key}" }
}

# ---------------------------------------------------------------- Subnets privadas

resource "aws_subnet" "private" {
  for_each = local.private_subnets

  vpc_id            = aws_vpc.this.id
  availability_zone = each.key
  cidr_block        = each.value

  tags = { Name = "${var.name}-private-${each.key}", Tier = "private" }
}

# Una tabla de rutas por zona: cada una sale por el NAT de su zona,
# o por el único NAT si single_nat_gateway = true.
resource "aws_route_table" "private" {
  for_each = local.private_subnets

  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name}-private-${each.key}" }
}

resource "aws_route" "private_nat" {
  for_each = aws_route_table.private

  route_table_id         = each.value.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[var.single_nat_gateway ? local.azs[0] : each.key].id
}

resource "aws_route_table_association" "private" {
  for_each = aws_subnet.private

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private[each.key].id
}

# Endpoint gateway de S3 (gratis): las capas de las imágenes de ECR se bajan
# de S3, así ese tráfico no pasa por el NAT (que cobra por GB).
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${data.aws_region.current.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [for rt in aws_route_table.private : rt.id]

  tags = { Name = "${var.name}-s3-endpoint" }
}


