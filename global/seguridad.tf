# Alertas de seguridad del escaneo de imágenes (DEVOPS-46).
#
#   push a ECR ─► escaneo básico (scan_on_push) ─► evento "ECR Image Scan"
#     ─► regla de EventBridge ─► Lambda ─► ¿hay CRITICAL o HIGH? ─► SNS ─► mail
#
# Va en global/ porque los repositorios de ECR son compartidos: una imagen se
# escanea una sola vez, cuando se publica, antes de promoverse a test y prod.

data "aws_caller_identity" "current" {}

# En AWS Academy no se pueden crear roles de IAM: la Lambda usa LabRole.
data "aws_iam_role" "lab_role" {
  name = "LabRole"
}

locals {
  lambda_nombre = "${var.repository_prefix}-alertas-escaneo-ecr"
}

resource "aws_sns_topic" "seguridad" {
  name = "${var.repository_prefix}-seguridad"
  # Cifrado con la clave administrada por AWS: la Lambda publica con LabRole,
  # que puede usarla (a diferencia de CloudWatch en las alarmas de los ambientes).
  kms_master_key_id = "alias/aws/sns"
}

resource "aws_sns_topic_subscription" "email" {
  count = var.alert_email == "" ? 0 : 1

  topic_arn = aws_sns_topic.seguridad.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

data "archive_file" "lambda" {
  type        = "zip"
  source_file = "${path.module}/lambda/alertas_escaneo_ecr/handler.py"
  output_path = "${path.module}/.build/alertas_escaneo_ecr.zip"
}

resource "aws_cloudwatch_log_group" "lambda" {
  #checkov:skip=CKV_AWS_158:Logs cifrados con la clave administrada por CloudWatch; una CMK suma costo
  #checkov:skip=CKV_AWS_338:Retención de 14 días (costo, DEVOPS-47); el log solo dice qué imagen se escaneó

  name              = "/aws/lambda/${local.lambda_nombre}"
  retention_in_days = 14
}

resource "aws_lambda_function" "alertas_escaneo" {
  #checkov:skip=CKV_AWS_117:No usa recursos de la VPC (solo ECR y SNS): dentro de una VPC necesitaría NAT o endpoints
  #checkov:skip=CKV_AWS_116:Invocación asíncrona desde EventBridge, que ya reintenta; un aviso perdido se ve igual en la consola de ECR
  #checkov:skip=CKV_AWS_115:En Academy el límite de concurrencia de la cuenta es bajo; reservar concurrencia puede hacer fallar el apply
  #checkov:skip=CKV_AWS_173:Las variables de entorno no tienen secretos (ARN del topic y severidades); quedan cifradas con la clave de AWS
  #checkov:skip=CKV_AWS_50:X-Ray necesita permisos que LabRole puede no tener (si faltan, falla la creación); el log alcanza para una función de 1 paso
  #checkov:skip=CKV_AWS_272:Code signing necesita AWS Signer y un perfil de firma; el código lo despliega solo este pipeline

  function_name = local.lambda_nombre
  description   = "Avisa por SNS cuando el escaneo de ECR encuentra vulnerabilidades CRITICAL o HIGH (DEVOPS-46)"
  role          = data.aws_iam_role.lab_role.arn
  runtime       = "python3.13"
  handler       = "handler.handler"
  timeout       = 30
  memory_size   = 128

  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256

  environment {
    variables = {
      TOPIC_ARN   = aws_sns_topic.seguridad.arn
      SEVERIDADES = join(",", var.scan_alert_severities)
    }
  }

  depends_on = [aws_cloudwatch_log_group.lambda]
}

resource "aws_cloudwatch_event_rule" "escaneo_ecr" {
  name        = "${var.repository_prefix}-escaneo-ecr"
  description = "Escaneo terminado de una imagen de los repositorios ${var.repository_prefix}/* (DEVOPS-46)"

  event_pattern = jsonencode({
    source        = ["aws.ecr"]
    "detail-type" = ["ECR Image Scan"]
    detail = {
      "repository-name" = [{ prefix = "${var.repository_prefix}/" }]
      "scan-status"     = ["COMPLETE"]
    }
  })
}

resource "aws_cloudwatch_event_target" "lambda" {
  rule = aws_cloudwatch_event_rule.escaneo_ecr.name
  arn  = aws_lambda_function.alertas_escaneo.arn
}

resource "aws_lambda_permission" "eventbridge" {
  statement_id   = "PermitirEventBridge"
  action         = "lambda:InvokeFunction"
  function_name  = aws_lambda_function.alertas_escaneo.function_name
  principal      = "events.amazonaws.com"
  source_arn     = aws_cloudwatch_event_rule.escaneo_ecr.arn
  source_account = data.aws_caller_identity.current.account_id
}
