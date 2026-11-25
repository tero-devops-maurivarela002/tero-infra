# Observabilidad de un ambiente (DEVOPS-49, DEVOPS-50, DEVOPS-51):
#   - topic SNS "alertas" (lo usan las alarmas y la Lambda de seguridad);
#   - dashboard de operación;
#   - alarma de disponibilidad y alarmas de errores y latencia, cada una con
#     el link a su runbook en la descripción.
#
# Criterio (lab T10-04): se alerta sobre SÍNTOMAS que ve el usuario (la tienda
# no responde, da errores o está lenta), no sobre causas (CPU alta). Las causas
# están en el dashboard para diagnosticar. Varios períodos seguidos para evitar
# el "flapping".

resource "aws_sns_topic" "alertas" {
  #checkov:skip=CKV_AWS_26:CloudWatch Alarms no puede publicar en un topic cifrado con la clave administrada aws/sns; una CMK propia suma costo y en Academy no hay roles para su política. Los mensajes no llevan secretos.
  name = "${var.name}-alertas"
}

resource "aws_sns_topic_subscription" "email" {
  count = var.alert_email == "" ? 0 : 1

  topic_arn = aws_sns_topic.alertas.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

locals {
  alb = ["LoadBalancer", var.alb_arn_suffix]
  ui  = ["TargetGroup", var.ui_target_group_arn_suffix, "LoadBalancer", var.alb_arn_suffix]
}

# ---- DEVOPS-50: disponibilidad. La tienda (ui) sin ninguna tarea sana.
# Mínimo de HealthyHostCount < 1 durante 2 minutos seguidos. Sin datos =
# alarma: si el ALB no reporta, tampoco hay nadie atendiendo.
resource "aws_cloudwatch_metric_alarm" "disponibilidad" {
  alarm_name        = "${var.name}-disponibilidad"
  alarm_description = "La tienda no tiene ninguna tarea sana detrás del ALB: los usuarios ven 503. Runbook: ${var.runbook_base_url}/alerta-disponibilidad.md"

  namespace   = "AWS/ApplicationELB"
  metric_name = "HealthyHostCount"
  dimensions = {
    TargetGroup  = var.ui_target_group_arn_suffix
    LoadBalancer = var.alb_arn_suffix
  }
  statistic           = "Minimum"
  period              = 60
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  comparison_operator = "LessThanThreshold"
  threshold           = 1
  treat_missing_data  = "breaching"

  alarm_actions = [aws_sns_topic.alertas.arn]
  ok_actions    = [aws_sns_topic.alertas.arn]
}

# ---- DEVOPS-51: errores. Porcentaje de 5xx (del ALB y de los targets) sobre
# el total de pedidos, en 3 de los últimos 5 minutos. Con poco tráfico no
# dispara por un error suelto: hacen falta al menos 10 pedidos en el minuto.
resource "aws_cloudwatch_metric_alarm" "errores" {
  alarm_name        = "${var.name}-errores-5xx"
  alarm_description = "Más del ${var.error_rate_threshold}% de los pedidos a la tienda terminan en 5xx. Runbook: ${var.runbook_base_url}/alerta-errores-y-latencia.md"

  evaluation_periods  = 5
  datapoints_to_alarm = 3
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.error_rate_threshold
  treat_missing_data  = "notBreaching"

  metric_query {
    id          = "tasa"
    label       = "Porcentaje de 5xx"
    return_data = true
    # Sin tráfico suficiente la tasa vale 0 (no se alarma por 1 de 2 pedidos).
    expression = "IF(pedidos >= 10, 100 * (FILL(e5xx_target, 0) + FILL(e5xx_alb, 0)) / pedidos, 0)"
  }

  metric_query {
    id = "pedidos"
    metric {
      namespace   = "AWS/ApplicationELB"
      metric_name = "RequestCount"
      dimensions  = { LoadBalancer = var.alb_arn_suffix }
      stat        = "Sum"
      period      = 60
    }
  }

  metric_query {
    id = "e5xx_target"
    metric {
      namespace   = "AWS/ApplicationELB"
      metric_name = "HTTPCode_Target_5XX_Count"
      dimensions  = { LoadBalancer = var.alb_arn_suffix }
      stat        = "Sum"
      period      = 60
    }
  }

  metric_query {
    id = "e5xx_alb"
    metric {
      namespace   = "AWS/ApplicationELB"
      metric_name = "HTTPCode_ELB_5XX_Count"
      dimensions  = { LoadBalancer = var.alb_arn_suffix }
      stat        = "Sum"
      period      = 60
    }
  }

  alarm_actions = [aws_sns_topic.alertas.arn]
  ok_actions    = [aws_sns_topic.alertas.arn]
}

# ---- DEVOPS-51: rendimiento. Latencia p95 del ALB por encima del umbral en
# 3 de los últimos 5 minutos.
resource "aws_cloudwatch_metric_alarm" "latencia" {
  alarm_name        = "${var.name}-latencia-p95"
  alarm_description = "La latencia p95 de la tienda supera ${var.latency_p95_threshold_seconds} s. Runbook: ${var.runbook_base_url}/alerta-errores-y-latencia.md"

  namespace           = "AWS/ApplicationELB"
  metric_name         = "TargetResponseTime"
  dimensions          = { LoadBalancer = var.alb_arn_suffix }
  extended_statistic  = "p95"
  period              = 60
  evaluation_periods  = 5
  datapoints_to_alarm = 3
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.latency_p95_threshold_seconds
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.alertas.arn]
  ok_actions    = [aws_sns_topic.alertas.arn]
}

# ---- DEVOPS-49: dashboard de operación (uno por ambiente).
resource "aws_cloudwatch_dashboard" "operacion" {
  dashboard_name = "${var.name}-operacion"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "alarm", x = 0, y = 0, width = 24, height = 3
        properties = {
          title  = "Alarmas"
          alarms = [aws_cloudwatch_metric_alarm.disponibilidad.arn, aws_cloudwatch_metric_alarm.errores.arn, aws_cloudwatch_metric_alarm.latencia.arn]
        }
      },
      {
        type = "metric", x = 0, y = 3, width = 8, height = 6
        properties = {
          title  = "Pedidos por minuto (ALB)"
          region = var.aws_region
          view   = "timeSeries"
          stat   = "Sum"
          period = 60
          metrics = [
            concat(["AWS/ApplicationELB", "RequestCount"], local.alb, [{ label = "pedidos" }]),
          ]
        }
      },
      {
        type = "metric", x = 8, y = 3, width = 8, height = 6
        properties = {
          title  = "Latencia p95 y p99 (s)"
          region = var.aws_region
          view   = "timeSeries"
          period = 60
          metrics = [
            concat(["AWS/ApplicationELB", "TargetResponseTime"], local.alb, [{ stat = "p95", label = "p95" }]),
            concat(["AWS/ApplicationELB", "TargetResponseTime"], local.alb, [{ stat = "p99", label = "p99" }]),
          ]
          annotations = { horizontal = [{ label = "umbral de la alarma", value = var.latency_p95_threshold_seconds }] }
        }
      },
      {
        type = "metric", x = 16, y = 3, width = 8, height = 6
        properties = {
          title  = "Errores 5xx y 4xx por minuto"
          region = var.aws_region
          view   = "timeSeries"
          stat   = "Sum"
          period = 60
          metrics = [
            concat(["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count"], local.alb, [{ label = "5xx de los servicios" }]),
            concat(["AWS/ApplicationELB", "HTTPCode_ELB_5XX_Count"], local.alb, [{ label = "5xx del ALB" }]),
            concat(["AWS/ApplicationELB", "HTTPCode_Target_4XX_Count"], local.alb, [{ label = "4xx" }]),
          ]
        }
      },
      {
        type = "metric", x = 0, y = 9, width = 8, height = 6
        properties = {
          title  = "Tareas sanas de la tienda (ui)"
          region = var.aws_region
          view   = "timeSeries"
          stat   = "Minimum"
          period = 60
          metrics = [
            concat(["AWS/ApplicationELB", "HealthyHostCount"], local.ui, [{ label = "sanas" }]),
            concat(["AWS/ApplicationELB", "UnHealthyHostCount"], local.ui, [{ label = "no sanas" }]),
          ]
        }
      },
      {
        type = "metric", x = 8, y = 9, width = 8, height = 6
        properties = {
          title  = "CPU por servicio (% de lo reservado)"
          region = var.aws_region
          view   = "timeSeries"
          stat   = "Average"
          period = 60
          metrics = [for s in var.service_names :
            ["AWS/ECS", "CPUUtilization", "ClusterName", var.cluster_name, "ServiceName", s, { label = s }]
          ]
        }
      },
      {
        type = "metric", x = 16, y = 9, width = 8, height = 6
        properties = {
          title  = "Memoria por servicio (% de lo reservado)"
          region = var.aws_region
          view   = "timeSeries"
          stat   = "Average"
          period = 60
          metrics = [for s in var.service_names :
            ["AWS/ECS", "MemoryUtilization", "ClusterName", var.cluster_name, "ServiceName", s, { label = s }]
          ]
        }
      },
      {
        type = "metric", x = 0, y = 15, width = 24, height = 6
        properties = {
          title  = "Tareas corriendo por servicio (Container Insights)"
          region = var.aws_region
          view   = "timeSeries"
          stat   = "Minimum"
          period = 60
          metrics = [for s in var.service_names :
            ["ECS/ContainerInsights", "RunningTaskCount", "ClusterName", var.cluster_name, "ServiceName", s, { label = s }]
          ]
        }
      },
    ]
  })
}
