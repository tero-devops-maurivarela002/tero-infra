# Tarea única "db-init": crea las bases catalogdb y cartdb y la tabla
# cart_items en RDS (lo mismo que init-db.sql en docker-compose).
#
# No es un servicio: se corre a mano una vez por ambiente, después del primer
# apply, con scripts/inicializar-db.sh. Es idempotente (se puede repetir).

resource "aws_cloudwatch_log_group" "db_init" {
  #checkov:skip=CKV_AWS_158:Logs cifrados con la clave administrada por CloudWatch; una CMK suma costo
  #checkov:skip=CKV_AWS_338:Retención decidida en DEVOPS-47 (costo); la tarea solo inicializa la base

  name              = "/tero/${var.environment}/db-init"
  retention_in_days = var.log_retention_days
}

locals {
  db_init_sql = <<-SQL
    SELECT 'CREATE DATABASE catalogdb' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'catalogdb')\gexec
    SELECT 'CREATE DATABASE cartdb' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'cartdb')\gexec
    \c cartdb
    CREATE TABLE IF NOT EXISTS cart_items (
        customer_id VARCHAR(255) NOT NULL,
        item_id     VARCHAR(255) NOT NULL,
        quantity    INTEGER      NOT NULL,
        unit_price  INTEGER      NOT NULL,
        PRIMARY KEY (customer_id, item_id)
    );
    SELECT 'db-init OK: ' || string_agg(datname, ', ') FROM pg_database WHERE datname IN ('orders', 'catalogdb', 'cartdb');
  SQL
}

resource "aws_ecs_task_definition" "db_init" {
  #checkov:skip=CKV_AWS_249:En AWS Academy el único rol disponible es LabRole

  family                   = "${local.name}-db-init"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = data.aws_iam_role.lab.arn
  task_role_arn            = data.aws_iam_role.lab.arn

  container_definitions = jsonencode([{
    name      = "db-init"
    image     = "public.ecr.aws/docker/library/postgres:${var.db_engine_version}-alpine"
    essential = true

    # El SQL viaja en una variable (no es secreto) y psql lo lee de stdin.
    command = ["sh", "-c", "printf '%s\\n' \"$INIT_SQL\" | psql -v ON_ERROR_STOP=1 -d orders"]

    environment = [
      { name = "PGHOST", value = module.database.db_address },
      { name = "PGPORT", value = tostring(module.database.db_port) },
      { name = "INIT_SQL", value = local.db_init_sql },
    ]
    secrets = [
      { name = "PGUSER", valueFrom = "${module.database.db_secret_arn}:username::" },
      { name = "PGPASSWORD", valueFrom = "${module.database.db_secret_arn}:password::" },
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.db_init.name
        awslogs-region        = var.aws_region
        awslogs-stream-prefix = "db-init"
      }
    }
  }])
}
