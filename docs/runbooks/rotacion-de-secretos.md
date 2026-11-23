# Runbook: rotación de secretos

- **Tarea:** DEVOPS-35
- **Relacionado:** [ADR-003](../adr/ADR-003-ecs-base-de-datos-y-secretos.md) (cómo se generan e inyectan), [checkov.md](../seguridad/checkov.md) (CKV2_AWS_57, CKV_AWS_31)

Este documento dice **qué secretos tiene Tero, dónde viven y cómo se cambian** sin cortar el servicio y sin que la contraseña pase por el repo, el state o el chat.

## 1. Inventario

| Secreto | Dónde vive | Quién lo usa | Cómo se genera | Cómo se rota | Frecuencia |
|---|---|---|---|---|---|
| Contraseña de PostgreSQL | Secrets Manager `tero-<entorno>/database` y RDS | catalog, carts, orders, admin, db-init | Terraform (`ephemeral random_password`, 24 caracteres) | [Procedimiento A](#a-contraseña-de-la-base) | prod cada 90 días; siempre que alguien con acceso deje el equipo |
| Usuario, contraseña y clave JWT del admin | Secrets Manager `tero-<entorno>/admin` | admin | Terraform (24 y 64 caracteres) | [Procedimiento B](#b-panel-de-administración) | igual que la base |
| Credenciales de AWS del pipeline (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`) | GitHub → Settings → Secrets → Actions, en **tero-app y tero-infra** | CI/CD (push a ECR, deploy, Terraform) | AWS Academy, al iniciar el lab | [Procedimiento C](#c-credenciales-de-aws-en-github) | **cada vez que se inicia el lab** (vencen a las ~4 horas) |
| `SONAR_TOKEN` | GitHub Actions **y** Dependabot de tero-app | job `sonarcloud` | SonarCloud | [Procedimiento D](#d-token-de-sonarcloud) | cada 90 días o si se filtra |
| `ADMIN_ALLOWED_CIDRS` | GitHub Actions de tero-infra | pipeline de Terraform | a mano (la IP de quien administra) | se edita el secret y se corre el pipeline | cuando cambia la IP |

`ADMIN_ALLOWED_CIDRS` no es una contraseña, pero es un dato personal (la IP de casa) y el repo es público, por eso va como secret.

**Redis no tiene contraseña** (AUTH token): está aislado por security group y cifrado en tránsito, pero queda como hallazgo abierto (CKV_AWS_31 en [checkov.md](../seguridad/checkov.md)).

## 2. Cómo llegan los secretos a los servicios

```
terraform apply ──(write-only)──► Secrets Manager ──(valueFrom, al arrancar la tarea)──► contenedor (variable de entorno)
                └─(password_wo)─► RDS
```

- La contraseña **no** queda en el repo, ni en el plan, ni en el state, ni en la task definition (solo el ARN del secreto). Se puede comprobar con `terraform state pull | grep -c <contraseña>` → 0 (evidencia en DEVOPS-43).
- ECS lee el secreto **solo cuando arranca una tarea**. Por eso, después de rotar, hay que reemplazar las tareas.
- Eso lo hace Terraform solo: cada servicio que usa un secreto tiene la variable de entorno `SECRETS_VERSION` (por ejemplo `db-1-admin-1`). Al subir la versión cambia la task definition y ECS reemplaza las tareas. Como esa variable sale de los recursos de los secretos, Terraform **primero** cambia la contraseña en RDS y en Secrets Manager y **después** actualiza los servicios (ver `ecs.tf`).

## 3. Procedimientos

### A. Contraseña de la base

1. Crear la rama desde `develop`: `feature/DEVOPS-XX-rotar-db-<entorno>`.
2. En `envs/<entorno>.tfvars`, subir en 1 `db_password_version` (por ejemplo de `1` a `2`). **Nunca** escribir la contraseña: la genera Terraform.
3. Abrir el PR. El plan del pipeline tiene que mostrar **solo** esto:
   - `module.database.aws_db_instance.this` → *update in-place* (`password_wo_version`).
   - `module.database.aws_secretsmanager_secret_version.db` → *update in-place*.
   - `module.service["catalog" | "carts" | "orders" | "admin"]`: task definition *must be replaced* y servicio *update in-place* (`SECRETS_VERSION`).

   Si aparece cualquier otro cambio (sobre todo un *replace* de RDS), no mergear y revisar.
4. Mergear. El pipeline aplica el plan revisado.
5. Verificar (ver [sección 4](#4-verificación)).

**Impacto esperado:** entre que RDS cambia la contraseña y las tareas nuevas quedan sanas (1 a 3 minutos), las tareas viejas siguen con sus conexiones abiertas, pero una conexión **nueva** de una tarea vieja falla. En dev no importa; en prod conviene rotar en un horario de poco tráfico. La mejora para cero cortes es usar dos usuarios de base y alternarlos (queda como mejora).

**test y prod:** el pipeline hoy aplica solo dev. En test/prod se hace el mismo PR y, después del merge, el apply a mano desde CloudShell con `-var-file=envs/<entorno>.tfvars` (ver README).

### B. Panel de administración

Igual que A, pero subiendo `admin_secret_version`. Cambia la contraseña del admin **y** la clave con la que se firman los JWT, así que **se cierran todas las sesiones abiertas del admin**. Solo se reinicia el servicio `admin`.

Para ver la contraseña nueva (en CloudShell, nunca pegarla en un chat, issue o commit):

```bash
aws secretsmanager get-secret-value --secret-id tero-<entorno>/admin --query SecretString --output text | jq
```

### C. Credenciales de AWS en GitHub

En AWS Academy las credenciales son temporales y cambian cada vez que se inicia el lab.

1. Academy → *Start Lab* → *AWS Details* → *AWS CLI: Show*.
2. En **tero-app** y en **tero-infra**: Settings → Secrets and variables → Actions → actualizar `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` y `AWS_SESSION_TOKEN`.
3. Verificar: en tero-infra, Actions → *Terraform* → *Run workflow* con `plan`. Tiene que terminar en verde.

Nunca guardarlas en archivos del repo, en `~/.aws` de una máquina compartida ni pegarlas en un chat. Si pasó, *End Lab* y *Start Lab* las invalida.

### D. Token de SonarCloud

1. SonarCloud → *My Account* → *Security* → generar un token nuevo.
2. En tero-app, actualizar `SONAR_TOKEN` en **Actions** y en **Dependabot** (si no, los PRs de Dependabot fallan en `sonarcloud`).
3. Correr el CI en algún PR y confirmar que el job `sonarcloud` pasa.
4. **Revocar el token viejo** en SonarCloud.

## 4. Verificación

Después de rotar la base o el admin (en CloudShell):

```bash
ENTORNO=dev
# 1. El secreto cambió recién
aws secretsmanager describe-secret --secret-id tero-${ENTORNO}/database --query LastChangedDate

# 2. Los servicios terminaron el despliegue (rolloutState = COMPLETED)
aws ecs describe-services --cluster tero-${ENTORNO} \
  --services catalog carts orders admin \
  --query 'services[].[serviceName, deployments[0].rolloutState]' --output table

# 3. La tienda responde y no hay errores en los logs (script de tero-app)
curl -s -o /dev/null -w "%{http_code}\n" "$(terraform output -raw alb_url)/api/catalog/products"
./scripts/consultar-logs.sh ${ENTORNO} 15     # la consulta 1-errores tiene que salir vacía
```

## 5. Si algo sale mal

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| Las tareas nuevas no arrancan (`ResourceInitializationError` al leer el secreto) | LabRole sin permiso o el secreto se borró | Ver el evento en la consola de ECS. El *circuit breaker* vuelve a la revisión anterior solo. |
| Los servicios dan 500 y los logs dicen *password authentication failed* | RDS y Secrets Manager quedaron con contraseñas distintas (por ejemplo, un apply cortado a la mitad) | Subir **otra vez** `db_password_version`: genera una contraseña nueva y la escribe en los dos lugares en el mismo apply. |
| RDS se recreó por otro cambio | La instancia nueva arranca con la contraseña de ese apply pero el secreto no cambió | Lo mismo: subir `db_password_version` en el mismo PR (también está en ADR-003). |

Volver a la versión anterior del número **no** devuelve la contraseña anterior: cualquier cambio del número genera una nueva. Siempre se sube.

## 6. Si un secreto se filtró

1. **Rotarlo ya** con el procedimiento que corresponda (A, B, C o D). Para C, *End Lab* invalida las credenciales al instante.
2. Si llegó a un commit, darlo por comprometido aunque se borre: el historial de un repo público ya pudo ser copiado. gitleaks corre en cada PR de tero-app justamente para frenarlo antes del merge.
3. Revisar los logs de los servicios y la consola de AWS por actividad rara desde la hora de la filtración.
4. Anotar qué pasó, cuándo y qué se rotó en el issue de la tarea.

## 7. Por qué no hay rotación automática

Secrets Manager puede rotar solo con una Lambda, pero esa Lambda necesita un rol de IAM propio y **AWS Academy no deja crear roles** (CKV2_AWS_57 en [checkov.md](../seguridad/checkov.md)). Tampoco se usó `manage_master_user_password` de RDS porque rota cada 7 días sin reiniciar las tareas (ver ADR-003). Con este procedimiento la rotación queda **versionada**: cada cambio es un PR con su plan revisado.
