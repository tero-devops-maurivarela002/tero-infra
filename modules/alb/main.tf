# Módulo reutilizable de ALB (DEVOPS-43). Se usa dos veces:
#
#   - público (internal = false): :80 -> ui (la tienda), :8081 -> admin.
#   - interno (internal = true): un puerto por servicio de backend
#     (catalog, carts, orders, checkout). Es como los servicios se encuentran
#     entre sí: en AWS Academy no se puede usar Cloud Map (DNS interno).
#
# Cada entrada de "listeners" crea un listener HTTP en ese puerto y un target
# group del mismo nombre. Los target groups son de tipo "ip" porque las
# tareas Fargate se registran por IP (modo de red awsvpc).

resource "aws_lb" "this" {
  #checkov:skip=CKV2_AWS_20:Sin dominio/certificado ACM no hay HTTPS al que redirigir (docs/seguridad/checkov.md)
  #checkov:skip=CKV2_AWS_28:WAF tiene costo fijo y no está habilitado en AWS Academy; riesgo aceptado (docs/seguridad/checkov.md)
  #checkov:skip=CKV_AWS_91:Access logs del ALB necesitan bucket con política de ELB; mejora planificada, se usan logs de los servicios
  #checkov:skip=CKV_AWS_150:La protección contra borrado es por ambiente (alb_deletion_protection: true en prod)

  name               = "${var.name}-alb"
  load_balancer_type = "application"
  internal           = var.internal
  subnets            = var.subnet_ids
  security_groups    = [var.security_group_id]

  drop_invalid_header_fields = true
  enable_deletion_protection = var.deletion_protection

  tags = { Name = "${var.name}-alb" }
}

resource "aws_lb_target_group" "this" {
  #checkov:skip=CKV_AWS_378:ALB -> tareas por HTTP dentro de la VPC (subnets privadas, SG solo desde el ALB); TLS termina en el ALB

  for_each = var.listeners

  name        = "${var.name}-${each.key}"
  vpc_id      = var.vpc_id
  port        = var.app_port
  protocol    = "HTTP"
  target_type = "ip"

  # Al sacar una tarea, esperar 30 s a que terminen sus requests (default 300).
  deregistration_delay = 30

  health_check {
    path                = var.health_check_path
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = { Name = "${var.name}-${each.key}" }
}

resource "aws_lb_listener" "this" {
  #checkov:skip=CKV_AWS_2:Sin dominio propio en AWS Academy no hay certificado ACM; HTTPS cuando haya dominio
  #checkov:skip=CKV_AWS_103:No aplica: el listener es HTTP (sin TLS) por falta de certificado; ver CKV_AWS_2

  for_each = var.listeners

  load_balancer_arn = aws_lb.this.arn
  port              = each.value
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this[each.key].arn
  }
}

# Los listeners se llamaban "http" y "admin" en la primera versión del módulo.
moved {
  from = aws_lb_listener.http
  to   = aws_lb_listener.this["ui"]
}

moved {
  from = aws_lb_listener.admin
  to   = aws_lb_listener.this["admin"]
}
