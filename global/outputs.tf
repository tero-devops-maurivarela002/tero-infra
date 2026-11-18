output "ecr_registry" {
  description = "Registry de ECR de la cuenta (para docker login y para armar la URL de las imágenes)."
  value       = split("/", values(aws_ecr_repository.this)[0].repository_url)[0]
}

output "ecr_repository_urls" {
  description = "URL de cada repositorio de ECR, por servicio."
  value       = { for k, r in aws_ecr_repository.this : k => r.repository_url }
}
