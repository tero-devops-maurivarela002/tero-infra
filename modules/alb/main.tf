# ALB público de Tero (DEVOPS-43).
#
#   :80   -> target group "ui"    (la tienda)
#   :8081 -> target group "admin" (panel de administración; el security group
#            del módulo network solo deja entrar a las IPs permitidas)
#
# Los target groups son de tipo "ip" porque las tareas Fargate tienen su
# propia interfaz de red (modo awsvpc) y se registran por IP.

resource "aws_lb" "this" {
  name               = "${var.name}-alb"
  load_balancer_type = "application"
  internal           = false
  subnets            = var.public_subnet_ids
  security_groups    = [var.security_group_id]

  drop_invalid_header_fields = true
  enable_deletion_protection = var.deletion_protection

  tags = { Name = "${var.name}-alb" }
}

resource "aws_lb_target_group" "this" {
  for_each = toset(["ui", "admin"])

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

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this["ui"].arn
  }
}

resource "aws_lb_listener" "admin" {
  load_balancer_arn = aws_lb.this.arn
  port              = var.admin_listener_port
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this["admin"].arn
  }
}
