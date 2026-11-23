# Pipeline de Terraform (DEVOPS-45)

Archivo: [`.github/workflows/terraform.yml`](../../.github/workflows/terraform.yml).

```
PR a develop ─► validate ─┬─► dev: plan de global/ y dev (se muestra en el resumen del run)
                checkov ──┘
merge a develop ─► validate + checkov ─► dev: plan ─► apply de ESE plan
```

| Job | Qué hace | Necesita AWS |
|---|---|---|
| `validate` | `terraform fmt -check`, `validate` (raíz y `global/`), `terraform test` (mock_provider) | no |
| `checkov` | Gate de seguridad de IaC ([checkov.md](../seguridad/checkov.md)) | no |
| `dev` | `plan` de `global/` (ECR) y de dev; en merge a develop, `apply` del plan guardado | sí |

## Decisiones

- **Se aplica el plan guardado** (`plan -out` → `apply <archivo>`), no un plan
  nuevo: lo que se ve en el resumen es exactamente lo que se aplica.
- **`global/` antes que dev**: los repositorios de ECR se comparten y dev los usa.
- **`image_tag` automático**: el CD de tero-app (DEVOPS-27) cambia la imagen de
  los servicios en cada merge. El pipeline toma el SHA de la **última revisión
  registrada** de la task definition de ui en dev (el CD la registra apenas
  arranca, así que un apply en paralelo con un deploy usa la versión nueva) (`scripts/ci/preparar-variables.sh`), así un apply de infraestructura
  no vuelve los servicios a una versión vieja. Se puede forzar uno con
  *Run workflow* → `image_tag`.
- **IP del admin fuera del repo**: secret `ADMIN_ALLOWED_CIDRS` (ej.
  `["1.2.3.4/32"]`), enmascarado en los logs. Sin el secret, el admin queda
  cerrado (lista vacía), que es lo seguro por defecto.
- **Un run a la vez** (`concurrency: terraform-dev`), además del lock del state
  en S3 (`use_lockfile`). Si alguien está corriendo un apply a mano (por
  ejemplo desde CloudShell), el pipeline espera hasta 15 minutos a que se libere
  el lock (`-lock-timeout=15m`) en lugar de fallar enseguida.
- **Versiones fijas**: Terraform 1.17.2 con checksum verificado, Checkov 3.4.5,
  acciones de GitHub por SHA.
- **test y prod**: se agregan en el Sprint 4, desde `main` y con aprobación manual
  (GitHub Environments).

## Requisitos

Secrets del repo tero-infra: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`,
`AWS_SESSION_TOKEN` (temporales en Academy: actualizarlos en cada sesión del
lab) y, opcional, `ADMIN_ALLOWED_CIDRS`.

Si el lab está apagado, `validate` y `checkov` pasan igual y `dev` falla al
autenticar: es esperado.

## Correr a mano

*Actions → Terraform → Run workflow*: `action = plan` o `apply`, e `image_tag`
opcional (obligatorio si dev no está levantado y se quiere crear desde cero).
