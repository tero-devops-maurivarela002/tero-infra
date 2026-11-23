# Pipeline de Terraform (DEVOPS-45, DEVOPS-28)

Archivos:
- [`.github/workflows/terraform.yml`](../../.github/workflows/terraform.yml): cuándo corre y qué ambiente toca.
- [`.github/workflows/terraform-ambiente.yml`](../../.github/workflows/terraform-ambiente.yml): workflow reutilizable, un ambiente por llamada.
- [`scripts/terraform-ambiente.sh`](../../scripts/terraform-ambiente.sh): la lógica (plan, apply, destroy y db-init). Corre igual en el pipeline y en CloudShell.

```
PR a develop   ─► validate ─┬─► dev: plan de global/ y de dev (en el resumen del run)
                  checkov ──┘
merge a develop ─► validate + checkov ─► dev: plan ─► apply de ESE plan ─► db-init

PR a main      ─► validate + checkov ─► test: plan ─► prod: plan
merge a main   ─► validate + checkov ─► test: plan ─► apply ─► db-init
                                          └─► prod: ⏸ aprobación manual ─► plan ─► apply ─► db-init
```

Git Flow (ADR-001): `develop` es dev, `main` es lo que sale a test y a prod.
Los cambios de infraestructura se prueban en dev antes de llegar a `main`.

| Job | Qué hace | Necesita AWS | Aprobación |
|---|---|---|---|
| `validate` | `terraform fmt -check`, `validate` (raíz y `global/`), `terraform test` (mock_provider) | no | no |
| `checkov` | Gate de seguridad de IaC ([checkov.md](../seguridad/checkov.md)) | no | no |
| `dev` | `plan` de `global/` (ECR) y de dev; en merge a develop, `apply` | sí | no |
| `test` | `plan` de test; en merge a main, `apply` | sí | no |
| `prod` | `plan` de prod; en merge a main, `apply` **después de test** | sí | **sí** (environment `production`) |

## Gates entre ambientes

- **dev → test/prod:** un cambio de infraestructura llega a `main` solo por PR
  desde `develop` (o `release/*`), así que antes pasó por `validate`, `checkov`
  y por un apply real en dev.
- **test → prod:** en un merge a `main`, prod corre después de test. Si el apply
  de test falla, prod ni arranca.
- **Aprobación manual en prod:** el job `prod` usa el environment de GitHub
  `production`, que tiene *required reviewers*. El run queda en pausa hasta
  que alguien lo aprueba en la pestaña Actions (**Review deployments**). Lo que
  se aprueba es el plan que se vio en el PR a `main`.

## Decisiones

- **Se aplica el plan guardado** (`plan -out` → `apply <archivo>`), no un plan
  nuevo: lo que se ve en el resumen es exactamente lo que se aplica.
- **Una key de state por ambiente** (`backend/<amb>.hcl`): un error en dev no
  puede tocar el state de prod.
- **`global/` solo desde dev**: los repositorios de ECR se comparten y se crean
  una sola vez. test y prod usan las mismas imágenes (se promueven, no se
  reconstruyen).
- **`db-init` después de cada apply**: crea `catalogdb`, `cartdb` y la tabla
  `cart_items` si no existen. Es idempotente, así que se corre siempre. Antes
  era manual, y en un ambiente recién creado catalog y carts no arrancaban
  (pasó el 23/11 al recrear dev).
- **`image_tag` automático** (`scripts/ci/preparar-variables.sh`), en este orden:
  1. el que se pide a mano (*Run workflow* → `image_tag`);
  2. el de la **última revisión registrada** de la task definition de ui del
     propio ambiente: el CD de tero-app cambia la imagen en cada deploy, y así
     un apply de infraestructura no vuelve los servicios a una versión vieja;
  3. si el ambiente está apagado, el del **ambiente anterior** (test toma el
     de dev; prod el de test o, si no, el de dev): un ambiente nuevo arranca
     con una versión que ya pasó por los anteriores;
  4. para dev recién creado, la última imagen publicada en ECR.
- **IP del admin fuera del repo**: secret `ADMIN_ALLOWED_CIDRS` (ej.
  `["1.2.3.4/32"]`), enmascarado en los logs. Sin el secret, el admin queda
  cerrado (lista vacía), que es lo seguro por defecto.
- **Un run a la vez por ambiente** (`concurrency: terraform-<amb>`), además del
  lock del state en S3 (`use_lockfile`). Si alguien está corriendo un apply a
  mano (por ejemplo desde CloudShell), el pipeline espera hasta 15 minutos a
  que se libere el lock (`-lock-timeout=15m`) en lugar de fallar enseguida.
- **Versiones fijas**: Terraform 1.17.2 con checksum verificado, Checkov 3.4.5,
  acciones de GitHub por SHA.
- **test y prod son efímeros en AWS Academy**: prod cuesta unos USD 10 por día
  (2 NAT, RDS Multi-AZ, 2 tareas por servicio). Se prenden para probar y sacar
  evidencias, y se apagan con *Run workflow* → `destroy`
  ([runbook](../runbooks/prender-el-lab.md#4-apagar)).

## Requisitos

Secrets del repo tero-infra: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`,
`AWS_SESSION_TOKEN` (temporales en Academy: actualizarlos en cada sesión del
lab) y, opcional, `ADMIN_ALLOWED_CIDRS`.

Environments (Settings → Environments): `dev`, `test` y `production`. Solo
`production` tiene protección: *Required reviewers* (`maurivarela002` y
`mauriciovarela-2inn`).

Si el lab está apagado, `validate` y `checkov` pasan igual y los jobs de los
ambientes fallan al autenticar: es esperado.

## Correr a mano

*Actions → Terraform → Run workflow*, con `ambiente` (dev, test o prod),
`action` (plan, apply o destroy) e `image_tag` opcional. Correrlo desde la rama
`develop` para dev y desde `main` para test y prod. En prod, `apply` y
`destroy` esperan la aprobación.

Desde CloudShell es lo mismo:

```bash
cd ~/tero-infra && git pull
./scripts/terraform-ambiente.sh dev plan      # o apply / destroy, y test / prod
```
