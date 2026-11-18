output "account_id" {
  description = "ID de la cuenta de AWS donde se aplicó este ambiente (sirve para confirmar que estamos en el lab correcto)."
  value       = data.aws_caller_identity.current.account_id
}

output "region" {
  description = "Región de AWS usada por el provider."
  value       = data.aws_region.current.region
}

output "environment" {
  description = "Ambiente al que corresponde este state (dev, test o prod)."
  value       = var.environment
}
