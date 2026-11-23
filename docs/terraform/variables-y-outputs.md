# Variables y outputs de Terraform

- **Tarea:** DEVOPS-44
- **Fuente de verdad:** `variables.tf` y `outputs.tf` (todas las variables y outputs tienen `description`). Este documento las junta en un solo lugar, con el valor de cada ambiente y de dónde sale.

## 1. De dónde sale el valor de cada variable

Terraform toma el valor con esta prioridad (gana el de más abajo):

| Origen | Qué va ahí | Versionado |
|---|---|---|
| `default` en `variables.tf` | Valores razonables para dev | Sí |
| `envs/<entorno>.tfvars` | Lo que cambia entre dev, test y prod (tamaños, alta disponibilidad, protecciones) | Sí |
| `$RUNNER_TEMP/ci.auto.tfvars.json` (lo arma `scripts/ci/preparar-variables.sh` en el pipeline) | `image_tag` (el SHA que ya corre en el ambiente) y `admin_allowed_cidrs` (del secret `ADMIN_ALLOWED_CIDRS`) | **No** |
| `-var` en la línea de comandos | Lo mismo que el anterior, cuando se aplica a mano desde CloudShell | **No** |

Regla: **en el repo va solo lo que no es sensible y no cambia en cada deploy.** Las contraseñas no son variables: las genera Terraform en el apply y van directo a Secrets Manager (ver [ADR-003](../adr/ADR-003-ecs-base-de-datos-y-secretos.md)). La IP del admin es un dato personal y el repo es público, por eso va como secret de GitHub.

## 2. Variables del ambiente (raíz)

"pipeline", "secret" y "a mano" quieren decir que el valor no está en el `.tfvars` y se pasa como explica la sección 1. Hoy el pipeline aplica solo dev; test y prod se aplican a mano.

| Variable | Tipo | Default | dev | test | prod | Para qué |
|---|---|---|---|---|---|---|
| `aws_region` | `string` | `"us-east-1"` | `"us-east-1"` | `"us-east-1"` | `"us-east-1"` | Región de AWS donde se despliega Tero. En AWS Academy es us-east-1. |
| `environment` | `string` | (obligatoria) | `"dev"` | `"test"` | `"prod"` | Nombre del ambiente: dev, test o prod. Se usa en nombres y etiquetas. |
| `vpc_cidr` | `string` | (obligatoria) | `"10.10.0.0/16"` | `"10.20.0.0/16"` | `"10.30.0.0/16"` | Rango de IPs de la VPC del ambiente. Uno distinto por ambiente para poder conectarlas en el futuro sin solaparse. |
| `az_count` | `number` | `2` | `2` | `2` | `2` | Cantidad de zonas de disponibilidad (2 alcanza para el ALB y Multi-AZ). |
| `single_nat_gateway` | `bool` | `true` | `true` | `true` | `false` | true: un NAT compartido (barato, dev y test). false: un NAT por zona (alta disponibilidad, prod). |
| `admin_allowed_cidrs` | `list(string)` | `[]` | secret | a mano | a mano | IPs (en formato CIDR, por ejemplo 1.2.3.4/32) que pueden entrar al panel de administración en el puerto 8081 del ALB. |
| `alb_deletion_protection` | `bool` | `false` | `false` | `false` | `true` | Protege el ALB contra borrados (prod). |
| `ecr_repository_prefix` | `string` | `"tero"` | — | — | — | Prefijo de los repositorios de ECR: las imágenes son `<registry>/<prefijo>/<servicio>`. |
| `image_tag` | `string` | (obligatoria) | pipeline | a mano | a mano | Tag de las imágenes a desplegar (el SHA del commit de tero-app). |
| `service_desired_count` | `number` | `1` | `1` | `1` | `2` | Tareas por servicio (1 en dev, 2 en prod para alta disponibilidad). |
| `service_cpu` | `number` | `256` | `256` | `256` | `256` | CPU por tarea en unidades de Fargate (256 = 0,25 vCPU). |
| `service_memory` | `number` | `512` | `512` | `512` | `512` | Memoria por tarea en MiB. |
| `log_retention_days` | `number` | `7` | `7` | `7` | `14` | Días de retención de los logs en CloudWatch (7 en dev, 14 en prod). |
| `admin_username` | `string` | `"admin"` | — | — | — | Usuario del panel de administración (la contraseña la genera Terraform y queda en Secrets Manager). |
| `admin_secret_version` | `number` | `1` | `1` | `1` | `1` | Subirla en 1 regenera la contraseña del admin y la clave JWT (rotación). |
| `db_engine_version` | `string` | `"16"` | — | — | — | Versión mayor de PostgreSQL. |
| `db_instance_class` | `string` | `"db.t3.micro"` | `"db.t3.micro"` | `"db.t3.micro"` | `"db.t3.micro"` | Tamaño de la instancia RDS. |
| `db_multi_az` | `bool` | `false` | `false` | `false` | `true` | RDS con réplica en espera en otra zona (prod). |
| `db_backup_retention_days` | `number` | `1` | `1` | `1` | `7` | Días de backups automáticos de RDS. |
| `db_deletion_protection` | `bool` | `false` | `false` | `false` | `true` | Protege RDS contra borrados (prod). |
| `db_skip_final_snapshot` | `bool` | `true` | `true` | `true` | `false` | No sacar snapshot final al destruir RDS (dev y test). |
| `db_password_version` | `number` | `1` | `1` | `1` | `1` | Subirla en 1 genera una contraseña nueva para la base (rotación). |
| `redis_node_type` | `string` | `"cache.t3.micro"` | `"cache.t3.micro"` | `"cache.t3.micro"` | `"cache.t3.micro"` | Tamaño del nodo de Redis. |
| `redis_replicas` | `number` | `0` | `0` | `0` | `1` | Réplicas de Redis además del primario. |

### Por qué cambian entre ambientes

| Tema | dev / test | prod | Motivo |
|---|---|---|---|
| Red | 1 NAT compartido | 1 NAT por zona | Si se cae una zona, la otra sigue saliendo a internet. Un NAT cuesta ~USD 1 por día. |
| Cómputo | 1 tarea por servicio | 2 tareas por servicio | Con 2, un deploy o una tarea caída no deja el servicio sin réplicas. |
| Base | Single-AZ, 1 día de backups, sin snapshot final | Multi-AZ, 7 días de backups, snapshot final | En prod los datos importan; en dev y test se recrean. |
| Redis | Sin réplica | 1 réplica | Failover automático en prod. |
| Protección contra borrado | No | ALB y RDS protegidos | Que un `destroy` por error no borre prod. |
| Logs | 7 días | 14 días | Más tiempo para investigar incidentes en prod. |
| VPC | `10.10.0.0/16` y `10.20.0.0/16` | `10.30.0.0/16` | Rangos distintos para poder conectar las VPCs en el futuro sin solaparse. |

`db_password_version` y `admin_secret_version` se suben en 1 para rotar contraseñas (runbook: [rotacion-de-secretos.md](../runbooks/rotacion-de-secretos.md)).

## 3. Recursos compartidos (`global/`)

Se aplican una sola vez por cuenta, no por ambiente.

| Variable | Tipo | Default | Para qué |
|---|---|---|---|
| `aws_region` | `string` | `"us-east-1"` | Región de AWS. |
| `repository_prefix` | `string` | `"tero"` | Los repositorios quedan como `<prefijo>/<servicio>`. |
| `services` | `set(string)` | `["catalog", "cart", "orders", "checkout", "ui", "admin"]` | Un repositorio de ECR por servicio. |
| `images_to_keep` | `number` | `30` | Imágenes que se guardan por repositorio; las más viejas se borran solas. |

| Output | Para qué |
|---|---|
| `ecr_registry` | Registry de ECR de la cuenta (`docker login` y URL de las imágenes). |
| `ecr_repository_urls` | URL de cada repositorio, por servicio. |

## 4. Outputs del ambiente

Se leen con `terraform output` (o `terraform output -raw <nombre>` para usarlos en scripts) después de `terraform init` del ambiente.

| Output | Qué devuelve | Quién lo usa |
|---|---|---|
| `account_id`, `region`, `environment` | Cuenta, región y ambiente del state | Confirmar que estamos en el lab y el ambiente correctos antes de un apply |
| `alb_url` | URL pública de la tienda | Personas, smoke tests |
| `admin_url` | URL del panel de administración (puerto 8081, solo desde `admin_allowed_cidrs`) | Personas |
| `vpc_id`, `public_subnet_ids`, `private_subnet_ids` | Red del ambiente | `scripts/inicializar-db.sh` (subnets privadas) |
| `nat_public_ips` | IPs por las que salen a internet los servicios | Si un servicio externo pide una IP fija para permitir el acceso |
| `ecs_cluster_name` | Nombre del cluster (`tero-<entorno>`) | `scripts/inicializar-db.sh`, CD de tero-app |
| `ecs_services` | Por servicio: nombre, familia de task definition y log group | CD de tero-app, consultas de logs (`/tero/<entorno>/<servicio>`) |
| `ecr_registry` | Registry de donde salen las imágenes | Referencia |
| `db_endpoint`, `redis_endpoint` | Host (y puerto) de PostgreSQL y Redis; solo accesibles desde los servicios | Diagnóstico |
| `db_secret_arn`, `admin_secret_arn` | ARN de los secretos en Secrets Manager | Ver o rotar credenciales |
| `db_init_task_definition`, `services_security_group_id` | Tarea que crea las bases y su security group | `scripts/inicializar-db.sh` |

Ningún output devuelve una contraseña: solo el ARN del secreto.

## 5. Variables de los módulos

Cada módulo de `modules/` documenta sus variables en su propio `variables.tf` (con `description` y, donde aplica, `validation`). La raíz es la única que las conecta: `main.tf` (red, ALBs, base) y `ecs.tf` (los 6 servicios).

| Módulo | Variables | Qué recibe de la raíz |
|---|---|---|
| `network` | 10 | `vpc_cidr`, `az_count`, `single_nat_gateway`, `admin_allowed_cidrs` |
| `alb` | 9 | Subnets, security group, puertos y destinos (se usa dos veces: público e interno) |
| `database` | 18 | Todas las `db_*` y `redis_*` |
| `ecs-service` | 18 | Imagen, CPU, memoria, cantidad de tareas, variables de entorno y secretos de cada servicio |

## 6. Cómo agregar una variable nueva

1. Declararla en `variables.tf` con `description`, `type` y, si se puede, `default` y `validation`.
2. Si cambia por ambiente, ponerla en los **tres** `envs/*.tfvars`.
3. Si es sensible, **no** va al `.tfvars`: se agrega a `scripts/ci/preparar-variables.sh` desde un secret de GitHub (y con `::add-mask::`).
4. Agregarla a la tabla de este documento.
5. El PR muestra el plan de dev; revisar que solo cambie lo esperado.
