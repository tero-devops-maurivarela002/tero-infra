# DEVOPS-46: la Lambda de seguridad se arma bien sin tocar AWS (mock_provider).
mock_provider "aws" {
  mock_data "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::123456789012:role/LabRole" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }
  mock_resource "aws_sns_topic" {
    defaults = { arn = "arn:aws:sns:us-east-1:123456789012:tero-seguridad" }
  }
  mock_resource "aws_lambda_function" {
    defaults = { arn = "arn:aws:lambda:us-east-1:123456789012:function:tero-alertas-escaneo-ecr" }
  }
  mock_resource "aws_cloudwatch_event_rule" {
    defaults = { arn = "arn:aws:events:us-east-1:123456789012:rule/tero-escaneo-ecr" }
  }
}

run "alertas_de_escaneo" {
  command = plan

  assert {
    condition     = aws_lambda_function.alertas_escaneo.environment[0].variables.SEVERIDADES == "CRITICAL,HIGH"
    error_message = "Por defecto la Lambda tiene que avisar de CRITICAL y HIGH."
  }

  assert {
    condition     = strcontains(aws_cloudwatch_event_rule.escaneo_ecr.event_pattern, "ECR Image Scan")
    error_message = "La regla de EventBridge tiene que escuchar los escaneos de ECR."
  }

  assert {
    condition     = aws_lambda_function.alertas_escaneo.role == "arn:aws:iam::123456789012:role/LabRole"
    error_message = "En Academy la Lambda tiene que usar LabRole."
  }

  assert {
    condition     = !output.scan_alert_email_subscribed
    error_message = "Sin alert_email no se suscribe ningún mail."
  }
}

run "con_email" {
  command = plan

  variables {
    alert_email = "alertas@example.com"
  }

  assert {
    condition     = output.scan_alert_email_subscribed
    error_message = "Con alert_email se suscribe el mail al topic de seguridad."
  }
}

run "severidad_invalida" {
  command = plan

  variables {
    scan_alert_severities = ["GRAVE"]
  }

  expect_failures = [var.scan_alert_severities]
}
