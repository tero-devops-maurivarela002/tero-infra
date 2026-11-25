# Secreto del panel de administración (usuario, contraseña y clave JWT).
#
# Igual que la contraseña de la base: los valores se generan con recursos
# ephemeral y se escriben con secret_string_wo, así que NO quedan en el state.
# Para ver la contraseña del admin:
#   aws secretsmanager get-secret-value --secret-id tero-<entorno>/admin \
#     --query SecretString --output text

ephemeral "random_password" "admin" {
  length  = 24
  special = false
}

ephemeral "random_password" "admin_jwt" {
  length  = 64
  special = false
}

resource "aws_secretsmanager_secret" "admin" {
  #checkov:skip=CKV2_AWS_57:La rotación automática requiere una Lambda con rol propio; rotación manual en el runbook (DEVOPS-35)
  #checkov:skip=CKV_AWS_149:Cifrado con la clave administrada por AWS (aws/secretsmanager)

  name                    = "${local.name}/admin"
  description             = "Credenciales del panel de administración de ${local.name} y clave para firmar los JWT."
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "admin" {
  secret_id = aws_secretsmanager_secret.admin.id

  secret_string_wo = jsonencode({
    username   = var.admin_username
    password   = ephemeral.random_password.admin.result
    jwt_secret = ephemeral.random_password.admin_jwt.result
  })
  secret_string_wo_version = var.admin_secret_version
}
