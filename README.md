# tero-infra

Infraestructura como código (Terraform) de Tero en AWS. La aplicación y sus pipelines están en [tero-app](https://github.com/tero-devops-maurivarela002/tero-app).

## Estructura

| Ruta | Qué tiene |
|---|---|
| `versions.tf` | Versión de Terraform y del provider de AWS, y el backend S3 (vacío, se completa en el `init`). |
| `providers.tf` | Provider de AWS con etiquetas comunes para todo lo que se crea. |
| `main.tf`, `ecs.tf`, `secrets.tf`, `db-init.tf` | Configuración raíz: instancia los módulos, el cluster ECS, los 6 servicios, el secreto del admin y la tarea de inicialización de la base. |
| `variables.tf`, `outputs.tf` | Variables y outputs (todos con `description`). |
| `modules/network` | VPC, subnets, NAT y security groups. |
| `modules/alb` | ALB con un listener y target group por servicio. Se usa dos veces: público (ui y admin) e interno (catalog, carts, orders y checkout). |
| `modules/database` | RDS PostgreSQL, ElastiCache Redis y el secreto de la base. |
| `modules/ecs-service` | Un microservicio en Fargate (reutilizable, se usa 6 veces). |
| `tests/` | `terraform test` con providers simulados (no toca AWS). |
| `backend/<entorno>.hcl` | Key del state, región, cifrado y lock de cada ambiente (y `global.hcl` para lo compartido). |
| `global/` | Recursos compartidos por los 3 ambientes: los repositorios de ECR (state propio). |
| `envs/<entorno>.tfvars` | Valores de cada ambiente (dev, test, prod). No llevan secretos. |
| `scripts/crear-bucket-state.sh` | Crea a mano el bucket del state (única pieza fuera de Terraform). |
| `scripts/inicializar-db.sh` | Corre la tarea `db-init` que crea `catalogdb`, `cartdb` y la tabla `cart_items`. |
| `docs/adr/` | Decisiones de arquitectura (ADR). |

## Prerrequisitos

- Terraform **1.11 o más nuevo** (lock nativo en S3 y atributos write-only para que los secretos no queden en el state).
- AWS CLI v2 y credenciales del lab de AWS Academy (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` y `AWS_SESSION_TOKEN`), o correr todo en AWS CloudShell dentro del lab.
- Región `us-east-1`.

### En AWS CloudShell

CloudShell no trae Terraform y el home tiene solo 1 GB, que no alcanza para el provider de AWS (~700 MB). Por eso Terraform se instala en `~/bin` y su carpeta de trabajo va a `/tmp`:

```bash
mkdir -p ~/bin && export PATH=$HOME/bin:$PATH
curl -sSLO https://releases.hashicorp.com/terraform/1.17.2/terraform_1.17.2_linux_amd64.zip
unzip -o terraform_1.17.2_linux_amd64.zip terraform -d ~/bin && rm terraform_1.17.2_linux_amd64.zip
export TF_DATA_DIR=/tmp/tf-data
```

`/tmp` se borra al cerrar la sesión: en cada sesión nueva hay que repetir los dos `export` y el `terraform init` (el state no se pierde, está en S3).

## Primera vez: crear el bucket del state

Una sola vez por cuenta (ver [ADR-002](docs/adr/ADR-002-backend-de-terraform.md)):

```bash
./scripts/crear-bucket-state.sh
```

Crea `tero-tfstate-<ID de la cuenta>` con versionado, cifrado, acceso público bloqueado y solo HTTPS. Si se vuelve a correr, no rompe nada.

## Recursos compartidos (ECR)

Una sola vez por cuenta, antes del primer push de imágenes. La misma imagen se promueve entre ambientes, así que ECR no depende del ambiente:

```bash
cd global
terraform init -backend-config=../backend/global.hcl -backend-config="bucket=${BUCKET}"
terraform plan -out=/tmp/tfplan-global && terraform apply /tmp/tfplan-global
cd ..
```

Crea `tero/catalog`, `tero/cart`, `tero/orders`, `tero/checkout`, `tero/ui` y `tero/admin`, con tags inmutables, *scan on push* y una política que guarda las últimas 30 imágenes.

## Uso por ambiente

```bash
ENTORNO=dev    # dev | test | prod
BUCKET="tero-tfstate-$(aws sts get-caller-identity --query Account --output text)"

terraform init -reconfigure \
  -backend-config="backend/${ENTORNO}.hcl" \
  -backend-config="bucket=${BUCKET}"

terraform plan  -var-file="envs/${ENTORNO}.tfvars" -var="image_tag=<sha de tero-app>" -out=tfplan
terraform apply tfplan

# Solo la primera vez en cada ambiente: crear las bases
./scripts/inicializar-db.sh
```

`image_tag` es el SHA del commit de tero-app cuya imagen está en ECR. En el día a día lo pasa el pipeline de CD.

## Probar sin AWS

```bash
terraform init -backend=false
terraform test
```

Arma el plan de dev con providers simulados y verifica, entre otras cosas, que haya 6 servicios, Container Insights activado y los log groups con el nombre acordado.

`-reconfigure` hace falta al cambiar de ambiente, porque cada uno tiene su propia key de state.

## Outputs

Ver `outputs.tf` (todos tienen `description`). Los más usados:

| Output | Para qué |
|---|---|
| `alb_url` | URL pública de la tienda. |
| `admin_url` | Panel de administración (solo desde `admin_allowed_cidrs`). |
| `ecs_cluster_name`, `ecs_services` | Nombres que usa el CD para `update-service`. |
| `db_secret_arn`, `admin_secret_arn` | Secretos en Secrets Manager. |
| `db_endpoint`, `redis_endpoint` | Solo accesibles desde los servicios. |

## Secretos

Ninguna contraseña está en el repo ni en el state: se generan en el `apply` y quedan en Secrets Manager (ver [ADR-003](docs/adr/ADR-003-ecs-base-de-datos-y-secretos.md)). Para ver la del panel admin:

```bash
aws secretsmanager get-secret-value --secret-id tero-dev/admin --query SecretString --output text
```
