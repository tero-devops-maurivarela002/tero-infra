# Runbook: prender el lab de nuevo (y apagarlo)

- **Tarea:** DEVOPS-28
- **Relacionado:** [pipeline de Terraform](../pipeline/terraform.md), [rotación de secretos](rotacion-de-secretos.md) (procedimiento C)

AWS Academy corta la sesión a las ~4 horas y **cambia las credenciales cada vez
que se hace Start Lab**. Para ahorrar crédito, los ambientes se destruyen al
final del día. Este runbook dice cómo volver a dejar todo andando.

## 1. Credenciales nuevas en GitHub (siempre)

1. En Academy: **Start Lab**, esperar el círculo verde, **AWS Details** → **Show** (AWS CLI).
2. Copiar los tres valores en **los dos repos** (tero-app **y** tero-infra):
   *Settings → Secrets and variables → Actions*:
   - `AWS_ACCESS_KEY_ID`
   - `AWS_SECRET_ACCESS_KEY`
   - `AWS_SESSION_TOKEN`

Si el ambiente sigue arriba (no se destruyó), con esto alcanza: re-correr el
run que falló con **Re-run failed jobs**.

## 2. Recrear el ambiente (si se destruyó)

*tero-infra → Actions → Terraform → Run workflow*:

| Campo | Valor |
|---|---|
| Rama | `develop` para dev, `main` para test y prod |
| `ambiente` | `dev` (o `test` / `prod`) |
| `action` | `apply` |
| `image_tag` | vacío (automático) o el SHA de tero-app que se quiere desplegar |

Tarda unos 15 minutos (sobre todo RDS). El job hace, en orden: plan, apply,
**db-init** (crea las bases de catalog y carts) y deja la URL de la tienda en
el resumen del run.

Con `image_tag` vacío se usa la última versión que corrió en ese ambiente, la
del ambiente anterior o, para dev, la última imagen publicada en ECR. Para
desplegar una versión puntual, poner el SHA completo de un commit de tero-app.

Desde CloudShell es lo mismo: `./scripts/terraform-ambiente.sh dev apply`.

## 3. Re-correr el CI de tero-app (si falló mientras el ambiente no existía)

*tero-app → Actions →* el run en rojo → **Re-run failed jobs**. Vuelve a correr
`deploy-dev` y los tests de integración contra dev.

## 4. Apagar

Al terminar el día, para no gastar crédito:

*tero-infra → Actions → Terraform → Run workflow* con `action = destroy` y el
ambiente. En prod pide aprobación y primero le saca la protección contra
borrado al ALB y a RDS (sin snapshot final: en Academy prod tiene solo datos de
prueba). Los repositorios de ECR **no** se borran (están en `global/`), así que
las imágenes quedan para la próxima.

Después: **End Lab** en Academy (o dejar que se corte solo).

## Síntomas y qué significan

| Síntoma | Dónde | Causa | Qué hacer |
|---|---|---|---|
| `The security token included in the request is invalid` / `ExpiredToken` | cualquier job con AWS | credenciales de una sesión anterior del lab | [paso 1](#1-credenciales-nuevas-en-github-siempre) |
| `DescribeTaskDefinition ... Unable to describe task definition` | `deploy-dev` de tero-app | el ambiente no existe (se destruyó) | [paso 2](#2-recrear-el-ambiente-si-se-destruyó) y después [paso 3](#3-re-correr-el-ci-de-tero-app-si-falló-mientras-el-ambiente-no-existía) |
| `Waiter ServicesStable failed`, con catalog y carts en `FAILED` y el resto sano | `deploy-dev` de tero-app | faltan las bases `catalogdb` y `cartdb` (db-init no corrió) | correr `./scripts/inicializar-db.sh` en CloudShell (o un `apply` del pipeline, que ya lo incluye) y después [paso 3](#3-re-correr-el-ci-de-tero-app-si-falló-mientras-el-ambiente-no-existía) |
| `No hay ninguna versión de tero-app para desplegar` | pipeline de Terraform | ambiente nuevo y ECR vacío | correr el workflow con `image_tag` = un SHA de develop de tero-app |
| `Error acquiring the state lock` | pipeline de Terraform o CloudShell | otro apply en curso sobre el mismo ambiente | esperar a que termine; si quedó colgado, ver el lock en S3 (`<amb>/terraform.tfstate.tflock`) |

Para ver por qué no arranca un servicio:

```bash
aws ecs describe-services --cluster tero-dev --services catalog \
  --query 'services[0].events[0:5].message' --output text
```
