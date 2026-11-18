output "alb_arn" {
  description = "ARN del ALB."
  value       = aws_lb.this.arn
}

output "alb_arn_suffix" {
  description = "Sufijo del ARN del ALB, el que usan las métricas y alarmas de CloudWatch."
  value       = aws_lb.this.arn_suffix
}

output "dns_name" {
  description = "Nombre DNS público del ALB (la URL de la tienda)."
  value       = aws_lb.this.dns_name
}

output "target_group_arns" {
  description = "ARN de los target groups, por servicio (ui y admin)."
  value       = { for k, tg in aws_lb_target_group.this : k => tg.arn }
}

output "target_group_arn_suffixes" {
  description = "Sufijo del ARN de los target groups, para métricas de CloudWatch."
  value       = { for k, tg in aws_lb_target_group.this : k => tg.arn_suffix }
}
