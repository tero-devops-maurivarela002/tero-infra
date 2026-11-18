# DEVOPS-43: evidencia del apply en dev (18/11/2026)

Corrido en AWS CloudShell (lab de AWS Academy), con `service_desired_count=0` porque las imágenes llegan a ECR en DEVOPS-26.

## Primer intento: Cloud Map no permitido

```
Error: creating Service Discovery Private DNS Namespace (dev.tero.local): ... api error AccessDeniedException:
User: arn:aws:sts::...:assumed-role/voclabs/... is not authorized to perform: servicediscovery:CreatePrivateDnsNamespace
```

Se reemplazó por un ALB interno (ver ADR-003).

## Plan después del cambio

`Plan: 24 to add, 0 to change, 3 to destroy.` Los 3 destroy, revisados antes de aplicar:

```
# module.network.aws_vpc_security_group_ingress_rule.services_from_services will be destroyed
# module.service["checkout"].aws_ecs_task_definition.this must be replaced
# module.service["ui"].aws_ecs_task_definition.this must be replaced
```

La regla ya no se usa y las task definitions son inmutables (cambió la URL interna, se registra una revisión nueva). Los listeners del ALB público aparecen como `has moved` (bloques `moved`, sin recrear).

## Apply

```
Apply complete! Resources: 24 added, 0 changed, 3 destroyed.

alb_url          = "http://tero-dev-alb-1656883427.us-east-1.elb.amazonaws.com"
admin_url        = "http://tero-dev-alb-1656883427.us-east-1.elb.amazonaws.com:8081"
db_endpoint      = "tero-dev-postgres.c3gsyuq8ykc5.us-east-1.rds.amazonaws.com:5432"
redis_endpoint   = "master.tero-dev-redis.expbqz.use1.cache.amazonaws.com"
ecs_cluster_name = "tero-dev"
ecs_services     = admin, carts, catalog, checkout, orders, ui (log groups /tero/dev/<servicio>)
```

## Inicialización de la base

```
=== Logs de db-init ===
CREATE DATABASE
CREATE DATABASE
You are now connected to database "cartdb" as user "retail_user".
CREATE TABLE
 db-init OK: orders, catalogdb, cartdb
✅ Base inicializada
```

## La contraseña no está en el state

```
$ PASS=$(aws secretsmanager get-secret-value --secret-id tero-dev/database ... ['password'])
$ echo "largo de la contraseña: ${#PASS}"
largo de la contraseña: 32
$ terraform state pull | grep -c "$PASS"
0
```

La contraseña existe en Secrets Manager (32 caracteres) y aparece 0 veces en el state, gracias a `ephemeral` + atributos write-only.
