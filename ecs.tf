# Cluster ECS y los 6 microservicios de Tero (DEVOPS-43).

# En AWS Academy no se pueden crear roles de IAM: todo usa LabRole
# (validado en DEVOPS-47 como execution role para logs y secretos).
data "aws_iam_role" "lab" {
  name = "LabRole"
}

resource "aws_ecs_cluster" "this" {
  name = local.name

  # Métricas de CPU y memoria por servicio y por tarea (validado en DEVOPS-47).
  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_ecs_cluster_capacity_providers" "this" {
  cluster_name       = aws_ecs_cluster.this.name
  capacity_providers = ["FARGATE"]
}

locals {
  # URL interna de cada servicio de backend: un puerto del ALB interno por
  # servicio (equivale a http://catalog:8080 en compose).
  url = { for svc, port in local.internal_ports : svc => "http://${module.internal_alb.dns_name}:${port}" }

  db_secret = module.database.db_secret_arn

  # Configuración de cada servicio, traducida de docker-compose.yml de tero-app.
  # Los valores sensibles van en "secrets" (Secrets Manager), nunca en "env".
  services = {
    catalog = {
      repository = "catalog"
      alb        = "internal"
      env = {
        GIN_MODE                            = "release"
        RETAIL_CATALOG_PERSISTENCE_PROVIDER = "postgres"
        RETAIL_CATALOG_PERSISTENCE_ENDPOINT = "${module.database.db_address}:${module.database.db_port}"
        RETAIL_CATALOG_PERSISTENCE_DB_NAME  = "catalogdb"
      }
      secrets = {
        RETAIL_CATALOG_PERSISTENCE_USER     = "${local.db_secret}:username::"
        RETAIL_CATALOG_PERSISTENCE_PASSWORD = "${local.db_secret}:password::"
      }
    }
    carts = {
      repository = "cart"
      alb        = "internal"
      env = {
        CART_PERSISTENCE_PROVIDER = "postgres"
        CART_POSTGRES_HOST        = module.database.db_address
        CART_POSTGRES_PORT        = tostring(module.database.db_port)
        CART_POSTGRES_DB          = "cartdb"
        PORT                      = "8080"
      }
      secrets = {
        CART_POSTGRES_USER     = "${local.db_secret}:username::"
        CART_POSTGRES_PASSWORD = "${local.db_secret}:password::"
      }
    }
    orders = {
      repository = "orders"
      alb        = "internal"
      env = {
        GIN_MODE                           = "release"
        RETAIL_ORDERS_PERSISTENCE_ENDPOINT = "${module.database.db_address}:${module.database.db_port}"
        RETAIL_ORDERS_PERSISTENCE_NAME     = "orders"
      }
      secrets = {
        RETAIL_ORDERS_PERSISTENCE_USERNAME = "${local.db_secret}:username::"
        RETAIL_ORDERS_PERSISTENCE_PASSWORD = "${local.db_secret}:password::"
      }
    }
    checkout = {
      repository = "checkout"
      alb        = "internal"
      env = {
        RETAIL_CHECKOUT_PERSISTENCE_PROVIDER  = "redis"
        RETAIL_CHECKOUT_PERSISTENCE_REDIS_URL = module.database.redis_url
        RETAIL_CHECKOUT_ENDPOINTS_ORDERS      = local.url["orders"]
      }
      secrets = {}
    }
    ui = {
      repository = "ui"
      alb        = "public"
      env = {
        RETAIL_UI_ENDPOINTS_CATALOG  = local.url["catalog"]
        RETAIL_UI_ENDPOINTS_CARTS    = local.url["carts"]
        RETAIL_UI_ENDPOINTS_CHECKOUT = local.url["checkout"]
        RETAIL_UI_ENDPOINTS_ORDERS   = local.url["orders"]
      }
      secrets = {}
    }
    admin = {
      repository = "admin"
      alb        = "public"
      env = {
        DB_HOST = module.database.db_address
        DB_PORT = tostring(module.database.db_port)
      }
      secrets = {
        DB_USER          = "${local.db_secret}:username::"
        DB_PASSWORD      = "${local.db_secret}:password::"
        ADMIN_USERNAME   = "${aws_secretsmanager_secret.admin.arn}:username::"
        ADMIN_PASSWORD   = "${aws_secretsmanager_secret.admin.arn}:password::"
        ADMIN_JWT_SECRET = "${aws_secretsmanager_secret.admin.arn}:jwt_secret::"
      }
    }
  }
}

module "service" {
  source   = "./modules/ecs-service"
  for_each = local.services

  name        = each.key
  name_prefix = local.name
  environment = var.environment
  cluster_arn = aws_ecs_cluster.this.arn

  image         = "${local.ecr_registry}/${var.ecr_repository_prefix}/${each.value.repository}:${var.image_tag}"
  cpu           = var.service_cpu
  memory        = var.service_memory
  desired_count = var.service_desired_count

  environment_variables = each.value.env
  secrets               = each.value.secrets

  subnet_ids         = module.network.private_subnet_ids
  security_group_ids = [module.network.services_security_group_id]

  execution_role_arn = data.aws_iam_role.lab.arn
  task_role_arn      = data.aws_iam_role.lab.arn

  target_group_arn   = each.value.alb == "public" ? module.alb.target_group_arns[each.key] : module.internal_alb.target_group_arns[each.key]
  log_retention_days = var.log_retention_days
}
