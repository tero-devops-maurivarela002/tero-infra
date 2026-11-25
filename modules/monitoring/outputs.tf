output "sns_topic_arn" {
  description = "ARN del topic SNS de alertas (alarmas y Lambda de seguridad)."
  value       = aws_sns_topic.alertas.arn
}

output "dashboard_name" {
  description = "Nombre del dashboard de operación en CloudWatch."
  value       = aws_cloudwatch_dashboard.operacion.dashboard_name
}

output "alarm_names" {
  description = "Nombres de las alarmas (disponibilidad, errores y latencia)."
  value = {
    disponibilidad = aws_cloudwatch_metric_alarm.disponibilidad.alarm_name
    errores        = aws_cloudwatch_metric_alarm.errores.alarm_name
    latencia       = aws_cloudwatch_metric_alarm.latencia.alarm_name
  }
}

output "alarm_descriptions" {
  description = "Descripción de cada alarma (incluye el link a su runbook)."
  value = {
    disponibilidad = aws_cloudwatch_metric_alarm.disponibilidad.alarm_description
    errores        = aws_cloudwatch_metric_alarm.errores.alarm_description
    latencia       = aws_cloudwatch_metric_alarm.latencia.alarm_description
  }
}

output "email_subscribed" {
  description = "Si hay una suscripción por email al topic de alertas."
  value       = length(aws_sns_topic_subscription.email) > 0
}
