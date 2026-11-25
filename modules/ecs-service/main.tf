# Módulo reutilizable: un microservicio de Tero en ECS Fargate (DEVOPS-43).
# Se instancia una vez por servicio con for_each desde la raíz.
#
# Crea: log group, task definition y el servicio ECS, registrado en el target
# group de un ALB (el público para ui/admin, el interno para el resto).

data "aws_region" "current" {}

# Un log group por servicio y ambiente, con retención (decisión de DEVOPS-47).
resource "aws_cloudwatch_log_group" "this" {
  #checkov:skip=CKV_AWS_158:Logs cifrados con la clave administrada por CloudWatch; una CMK suma costo
  #checkov:skip=CKV_AWS_338:Retención decidida en DEVOPS-47: 7 días dev/test, 14 prod (costo); no se guardan datos personales

  name              = "/tero/${var.environment}/${var.name}"
  retention_in_days = var.log_retention_days
}

resource "aws_ecs_task_definition" "this" {
  #checkov:skip=CKV_AWS_249:En AWS Academy el único rol disponible es LabRole (no se pueden crear roles separados)

  family                   = "${var.name_prefix}-${var.name}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = var.execution_role_arn
  task_role_arn            = var.task_role_arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([{
    name                   = var.name
    image                  = var.image
    essential              = true
    readonlyRootFilesystem = false

    portMappings = [{
      name          = var.name
      containerPort = var.container_port
      protocol      = "tcp"
    }]

    environment = [for k, v in var.environment_variables : { name = k, value = v }]
    secrets     = [for k, v in var.secrets : { name = k, valueFrom = v }]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.this.name
        awslogs-region        = data.aws_region.current.region
        awslogs-stream-prefix = "ecs"
      }
    }
  }])
}

resource "aws_ecs_service" "this" {
  name            = var.name
  cluster         = var.cluster_arn
  task_definition = aws_ecs_task_definition.this.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  # Si un deploy nuevo no levanta, ECS vuelve solo a la versión anterior.
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  health_check_grace_period_seconds = var.target_group_arn == null ? null : var.health_check_grace_period

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = var.security_group_ids
    assign_public_ip = false
  }

  dynamic "load_balancer" {
    for_each = var.target_group_arn == null ? [] : [var.target_group_arn]

    content {
      target_group_arn = load_balancer.value
      container_name   = var.name
      container_port   = var.container_port
    }
  }

  propagate_tags          = "SERVICE"
  enable_ecs_managed_tags = true
}
