output "ecr_registry" {
  description = "Registry de ECR de la cuenta (para docker login y para armar la URL de las imágenes)."
  value       = split("/", values(aws_ecr_repository.this)[0].repository_url)[0]
}

output "ecr_repository_urls" {
  description = "URL de cada repositorio de ECR, por servicio."
  value       = { for k, r in aws_ecr_repository.this : k => r.repository_url }
}

output "security_topic_arn" {
  description = "Topic de SNS de las alertas de seguridad del escaneo de ECR (DEVOPS-46)."
  value       = aws_sns_topic.seguridad.arn
}

output "scan_alert_lambda" {
  description = "Nombre de la Lambda que avisa de vulnerabilidades graves (para probarla con aws lambda invoke)."
  value       = aws_lambda_function.alertas_escaneo.function_name
}

output "scan_alert_email_subscribed" {
  description = "Si hay un email suscripto a las alertas de seguridad."
  value       = length(aws_sns_topic_subscription.email) > 0
}
