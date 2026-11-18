# ADR-002: Backend remoto del state de Terraform

- **Estado:** Aceptado
- **Fecha:** 17/11/2026
- **Decisores:** Mauricio Varela
- **Tarea relacionada:** DEVOPS-41

## Contexto

Terraform guarda en el *state* (`terraform.tfstate`) qué recursos creó y con qué IDs y atributos. Sin ese archivo no sabe qué hay en la nube y en el próximo `apply` intentaría crear todo de nuevo.

Condiciones que pesan en la decisión:

- El state **puede tener datos sensibles** (por ejemplo, atributos de la base de datos), así que no puede ir al repo ni quedar en una laptop.
- Lo van a usar **dos lugares**: la máquina de quien desarrolla y el pipeline de GitHub Actions (DEVOPS-45). Si dos `apply` corren a la vez sobre el mismo state, lo pueden corromper: hace falta un **lock**.
- Hay **tres ambientes** (dev, test y prod) y un error en dev no debería poder tocar prod.
- La letra pide que **todo** esté en Terraform salvo el bucket del state.
- Trabajamos en **AWS Academy**: no se pueden crear roles IAM y las credenciales vencen en cada sesión del lab.

## Decisión

1. **Bucket S3 creado a mano** con el script [`scripts/crear-bucket-state.sh`](../../scripts/crear-bucket-state.sh), con nombre `tero-tfstate-<ID de la cuenta>` (los nombres de bucket son únicos en todo AWS; el ID de la cuenta evita choques). El bucket tiene:
   - **Versionado**: cada `apply` guarda una versión nueva del state, así que si se rompe se puede volver a la anterior.
   - **Cifrado SSE-S3** por defecto y `encrypt = true` en el backend.
   - **Acceso público bloqueado** y una política que rechaza todo lo que no sea HTTPS.
   - **Ciclo de vida**: las versiones viejas se borran a los 90 días.
2. **Lock nativo de S3** (`use_lockfile = true`, disponible desde Terraform 1.10). Terraform crea un archivo `<key>.tflock` al lado del state mientras trabaja; si otro proceso intenta usar el mismo state, falla con un error de lock en vez de pisarlo.
3. **Una key por ambiente**: `dev/terraform.tfstate`, `test/terraform.tfstate` y `prod/terraform.tfstate`, configuradas en `backend/<entorno>.hcl`. Cada ambiente tiene su propio state y su propio lock.
4. **Configuración parcial del backend**: `versions.tf` declara `backend "s3" {}` vacío y los valores se pasan en el `init`. El nombre del bucket no se versiona (se pasa con `-backend-config="bucket=..."` o, en el pipeline, desde una variable de GitHub), así el ID de la cuenta no queda en el repo y cambiar de cuenta de Academy es cambiar un valor.

## Alternativas consideradas

### Lock con una tabla de DynamoDB

Es la forma "clásica" que se vio en el lab T05 06-01 (`dynamodb_table = "tero-tf-lock"`). La descartamos porque desde Terraform 1.10 el lock en S3 hace lo mismo sin un segundo recurso creado a mano, y HashiCorp marcó el lock con DynamoDB como *deprecated*. Si hiciera falta (por ejemplo, con una versión vieja de Terraform), se puede volver a DynamoDB agregando una línea al `.hcl`.

### Workspaces de Terraform (lab T05 07)

Un solo backend y `terraform workspace select dev|test|prod`. Funciona, pero es fácil olvidarse en qué workspace estás y aplicar en prod sin querer. Con un `.hcl` por ambiente, el ambiente queda explícito en el comando y en el pipeline.

### Terraform Cloud (lab T05 10-01)

Resuelve state, lock e historial sin crear nada en AWS. Lo descartamos porque agrega otra cuenta y otro lugar donde guardar las credenciales temporales de Academy, y la letra pide backend remoto pero no lo exige.

### Crear el bucket con Terraform

Es el problema del huevo y la gallina: Terraform necesita el bucket para guardar el state del propio bucket. Se puede hacer con un state local que después se migra, pero la letra permite crearlo a mano y es más simple de explicar.

## Consecuencias

- **Positivas:** el state no está en el repo ni en una laptop, queda cifrado y versionado, el pipeline y las personas no se pisan gracias al lock, y un error en un ambiente no toca a los otros.
- **Negativas:** el bucket es la única pieza fuera de Terraform, así que hay que documentarlo y recrearlo a mano si se cambia de cuenta (por eso es un script idempotente). Hay que usar Terraform 1.10 o más nuevo.
- **Si se traba un lock** (por ejemplo, se cortó un `apply` a la mitad porque venció la sesión del lab): confirmar que nadie más está aplicando y correr `terraform force-unlock <LOCK_ID>` con el ID que muestra el error.
- **Si se rompe el state:** en la consola de S3, "Mostrar versiones" en el objeto `<entorno>/terraform.tfstate` y restaurar la versión anterior.
