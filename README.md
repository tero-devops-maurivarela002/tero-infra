# tero-infra

Infraestructura como código (Terraform) de Tero en AWS. La aplicación y sus pipelines están en [tero-app](https://github.com/tero-devops-maurivarela002/tero-app).

## Estructura

| Ruta | Qué tiene |
|---|---|
| `versions.tf` | Versión de Terraform y del provider de AWS, y el backend S3 (vacío, se completa en el `init`). |
| `providers.tf` | Provider de AWS con etiquetas comunes para todo lo que se crea. |
| `variables.tf`, `outputs.tf`, `main.tf` | Configuración raíz. |
| `backend/<entorno>.hcl` | Key del state, región, cifrado y lock de cada ambiente. |
| `envs/<entorno>.tfvars` | Valores de cada ambiente (dev, test, prod). No llevan secretos. |
| `scripts/crear-bucket-state.sh` | Crea a mano el bucket del state (única pieza fuera de Terraform). |
| `docs/adr/` | Decisiones de arquitectura (ADR). |

## Prerrequisitos

- Terraform **1.10 o más nuevo** (por el lock nativo en S3).
- AWS CLI v2 y credenciales del lab de AWS Academy (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` y `AWS_SESSION_TOKEN`), o correr todo en AWS CloudShell dentro del lab.
- Región `us-east-1`.

## Primera vez: crear el bucket del state

Una sola vez por cuenta (ver [ADR-002](docs/adr/ADR-002-backend-de-terraform.md)):

```bash
./scripts/crear-bucket-state.sh
```

Crea `tero-tfstate-<ID de la cuenta>` con versionado, cifrado, acceso público bloqueado y solo HTTPS. Si se vuelve a correr, no rompe nada.

## Uso por ambiente

```bash
ENTORNO=dev    # dev | test | prod
BUCKET="tero-tfstate-$(aws sts get-caller-identity --query Account --output text)"

terraform init -reconfigure \
  -backend-config="backend/${ENTORNO}.hcl" \
  -backend-config="bucket=${BUCKET}"

terraform plan  -var-file="envs/${ENTORNO}.tfvars" -out=tfplan
terraform apply tfplan
```

`-reconfigure` hace falta al cambiar de ambiente, porque cada uno tiene su propia key de state.

## Outputs

| Output | Descripción |
|---|---|
| `account_id` | ID de la cuenta de AWS donde se aplicó el ambiente. |
| `region` | Región usada por el provider. |
| `environment` | Ambiente al que corresponde el state. |
