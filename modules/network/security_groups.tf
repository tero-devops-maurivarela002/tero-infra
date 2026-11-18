# Security groups de Tero (DEVOPS-42).
#
# Cadena de confianza: internet -> ALB -> servicios -> base de datos / Redis.
# Cada eslabón solo acepta tráfico del anterior, referenciando su security
# group (no rangos de IP). Esto resuelve la observación C de la auditoría:
# la base de datos y Redis ya no son alcanzables desde afuera.

# ---------------------------------------------------------------- ALB

resource "aws_security_group" "alb" {
  name        = "${var.name}-alb"
  description = "ALB publico de Tero: recibe HTTP desde internet"
  vpc_id      = aws_vpc.this.id
  tags        = { Name = "${var.name}-alb" }
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTP desde internet"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
}

resource "aws_vpc_security_group_egress_rule" "alb_to_services" {
  security_group_id            = aws_security_group.alb.id
  description                  = "Hacia los contenedores de Tero"
  referenced_security_group_id = aws_security_group.services.id
  ip_protocol                  = "tcp"
  from_port                    = var.app_port
  to_port                      = var.app_port
}

# ---------------------------------------------------------------- Servicios ECS

resource "aws_security_group" "services" {
  name        = "${var.name}-services"
  description = "Tareas ECS de Tero: solo aceptan trafico del ALB y entre ellas"
  vpc_id      = aws_vpc.this.id
  tags        = { Name = "${var.name}-services" }
}

resource "aws_vpc_security_group_ingress_rule" "services_from_alb" {
  security_group_id            = aws_security_group.services.id
  description                  = "Desde el ALB"
  referenced_security_group_id = aws_security_group.alb.id
  ip_protocol                  = "tcp"
  from_port                    = var.app_port
  to_port                      = var.app_port
}

# ui llama a catalog, carts, checkout y orders; checkout llama a orders.
resource "aws_vpc_security_group_ingress_rule" "services_from_services" {
  security_group_id            = aws_security_group.services.id
  description                  = "Entre servicios de Tero"
  referenced_security_group_id = aws_security_group.services.id
  ip_protocol                  = "tcp"
  from_port                    = var.app_port
  to_port                      = var.app_port
}

# Salida libre: hace falta para ECR, Secrets Manager y CloudWatch Logs
# (por el NAT) y para hablar con la base de datos y Redis.
resource "aws_vpc_security_group_egress_rule" "services_all" {
  security_group_id = aws_security_group.services.id
  description       = "Salida a AWS (ECR, Secrets Manager, Logs), DB y Redis"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# ---------------------------------------------------------------- Base de datos y Redis

resource "aws_security_group" "database" {
  name        = "${var.name}-database"
  description = "RDS PostgreSQL de Tero: solo desde los servicios"
  vpc_id      = aws_vpc.this.id
  tags        = { Name = "${var.name}-database" }
}

resource "aws_vpc_security_group_ingress_rule" "database_from_services" {
  security_group_id            = aws_security_group.database.id
  description                  = "PostgreSQL desde los servicios"
  referenced_security_group_id = aws_security_group.services.id
  ip_protocol                  = "tcp"
  from_port                    = var.postgres_port
  to_port                      = var.postgres_port
}

resource "aws_security_group" "redis" {
  name        = "${var.name}-redis"
  description = "ElastiCache Redis de Tero: solo desde los servicios"
  vpc_id      = aws_vpc.this.id
  tags        = { Name = "${var.name}-redis" }
}

resource "aws_vpc_security_group_ingress_rule" "redis_from_services" {
  security_group_id            = aws_security_group.redis.id
  description                  = "Redis desde los servicios"
  referenced_security_group_id = aws_security_group.services.id
  ip_protocol                  = "tcp"
  from_port                    = var.redis_port
  to_port                      = var.redis_port
}
