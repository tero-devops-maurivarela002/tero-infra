output "service_name" {
  description = "Nombre del servicio ECS."
  value       = aws_ecs_service.this.name
}

output "task_definition_arn" {
  description = "ARN de la revisión de task definition que creó Terraform."
  value       = aws_ecs_task_definition.this.arn
}

output "task_definition_family" {
  description = "Familia de la task definition (el CD registra revisiones nuevas sobre esta familia)."
  value       = aws_ecs_task_definition.this.family
}

output "log_group_name" {
  description = "Log group de CloudWatch del servicio."
  value       = aws_cloudwatch_log_group.this.name
}
