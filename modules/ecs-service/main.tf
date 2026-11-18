# Módulo reutilizable: un microservicio de Tero en ECS Fargate (DEVOPS-43).
# Se instancia una vez por servicio con for_each desde la raíz.
#
# Crea: log group, task definition, registro en Cloud Map (DNS interno) y el
# servicio ECS (con registro en el ALB si corresponde).

data "aws_region" "current" {}

# Un log group por servicio y ambiente, con retención (decisión de DEVOPS-47).
resource "aws_cloudwatch_log_group" "this" {
  name              = "/tero/${var.environment}/${var.name}"
  retention_in_days = var.log_retention_days
}

resource "aws_ecs_task_definition" "this" {
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

# Registro DNS interno: los demás servicios lo encuentran como
# http://<name>.<namespace>:8080 (igual que "http://catalog:8080" en compose).
resource "aws_service_discovery_service" "this" {
  name = var.name

  dns_config {
    namespace_id   = var.service_discovery_namespace_id
    routing_policy = "MULTIVALUE"

    dns_records {
      type = "A"
      ttl  = 10
    }
  }

  health_check_custom_config {}
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

  service_registries {
    registry_arn = aws_service_discovery_service.this.arn
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
