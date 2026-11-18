# Prueba de la configuración sin tocar AWS (terraform test con providers simulados).
# Verifica que el plan de dev se puede armar y que se cumplen reglas de seguridad
# básicas. Correr con: terraform init -backend=false && terraform test

mock_provider "aws" {
  mock_data "aws_availability_zones" {
    defaults = { names = ["us-east-1a", "us-east-1b", "us-east-1c"] }
  }
  mock_data "aws_region" {
    defaults = { region = "us-east-1" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }
  mock_data "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::123456789012:role/LabRole" }
  }
  mock_resource "aws_secretsmanager_secret" {
    defaults = { arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:tero-dev/x-AbCdEf" }
  }
  mock_resource "aws_lb" {
    defaults = { arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/tero-dev-alb/abc", dns_name = "tero-dev-alb-123.us-east-1.elb.amazonaws.com" }
  }
  mock_resource "aws_service_discovery_service" {
    defaults = { arn = "arn:aws:servicediscovery:us-east-1:123456789012:service/srv-abc" }
  }
  mock_resource "aws_ecs_cluster" {
    defaults = { arn = "arn:aws:ecs:us-east-1:123456789012:cluster/tero-dev" }
  }
  mock_resource "aws_lb_target_group" {
    defaults = { arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:targetgroup/tero-dev/abc" }
  }
}

mock_provider "random" {}

variables {
  environment = "dev"
  vpc_cidr    = "10.10.0.0/16"
  image_tag   = "abc1234"
}

run "plan_dev" {
  command = plan

  assert {
    condition     = length(module.service) == 6
    error_message = "Tienen que ser 6 servicios ECS."
  }

  assert {
    condition     = one([for s in aws_ecs_cluster.this.setting : s.value if s.name == "containerInsights"]) == "enabled"
    error_message = "Container Insights tiene que estar activado."
  }
}

# Con los providers simulados también se puede "aplicar" y mirar los outputs.
run "apply_dev_simulado" {
  command = apply

  assert {
    condition     = toset(keys(output.ecs_services)) == toset(["catalog", "carts", "orders", "checkout", "ui", "admin"])
    error_message = "Faltan servicios en el output ecs_services."
  }

  assert {
    condition     = output.ecs_services["catalog"].log_group == "/tero/dev/catalog"
    error_message = "Los log groups tienen que ser /tero/<entorno>/<servicio> (decisión de DEVOPS-47)."
  }

  assert {
    condition     = length(output.private_subnet_ids) == 2 && length(output.nat_public_ips) == 1
    error_message = "Dev usa 2 subnets privadas y un solo NAT."
  }
}

run "ambiente_invalido" {
  command = plan

  variables {
    environment = "staging"
  }

  expect_failures = [var.environment]
}
