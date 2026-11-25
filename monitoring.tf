# Observabilidad (DEVOPS-49, 50, 51): dashboard, alarmas y topic SNS de alertas.
module "monitoring" {
  source = "./modules/monitoring"

  name                       = local.name
  aws_region                 = var.aws_region
  cluster_name               = aws_ecs_cluster.this.name
  service_names              = keys(local.services)
  alb_arn_suffix             = module.alb.alb_arn_suffix
  ui_target_group_arn_suffix = module.alb.target_group_arn_suffixes["ui"]
  alert_email                = var.alert_email
  runbook_base_url           = "https://github.com/tero-devops-maurivarela002/tero-infra/blob/develop/docs/runbooks"
}
