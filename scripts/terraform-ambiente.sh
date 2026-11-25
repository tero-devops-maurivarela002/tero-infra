#!/usr/bin/env bash
# Plan, apply o destroy de UN ambiente (dev, test o prod) de Tero (DEVOPS-28).
#
# Uso:   ./scripts/terraform-ambiente.sh <dev|test|prod> <plan|apply|destroy>
# Ej.:   ./scripts/terraform-ambiente.sh test apply
#        INPUT_IMAGE_TAG=<sha> ./scripts/terraform-ambiente.sh dev apply
#
# Lo usa el pipeline (.github/workflows/terraform-ambiente.yml) y se puede
# correr igual desde CloudShell: hace lo mismo en los dos lados.
#
#   plan    -> plan de global/ (solo dev: repos de ECR) y del ambiente.
#   apply   -> plan + apply de ESE plan + db-init (crea catalogdb y cartdb;
#              es idempotente, así que se corre siempre y nunca se olvida).
#   destroy -> borra el ambiente. En prod primero apaga la protección contra
#              borrado del ALB y de RDS (ver la sección "Apagar test y prod"
#              de docs/runbooks/prender-el-lab.md).
#
# Variables opcionales:
#   INPUT_IMAGE_TAG      SHA de tero-app a usar (si no, lo elige preparar-variables.sh)
#   ADMIN_ALLOWED_CIDRS  IPs del admin, ej. ["1.2.3.4/32"] (secret del repo)
#   ALERT_EMAIL          email que recibe las alarmas (secret del repo)
set -euo pipefail

AMBIENTE="${1:?Falta el ambiente (dev, test o prod)}"
ACCION="${2:?Falta la acción (plan, apply o destroy)}"
case "$AMBIENTE" in dev|test|prod) ;; *) echo "Ambiente inválido: $AMBIENTE" >&2; exit 2 ;; esac
case "$ACCION" in plan|apply|destroy) ;; *) echo "Acción inválida: $ACCION" >&2; exit 2 ;; esac

cd "$(dirname "$0")/.."
TMP="${RUNNER_TEMP:-/tmp}"
SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/null}"
export TF_IN_AUTOMATION=true TF_INPUT=false

# preparar-variables.sh: bucket del state, image_tag e IPs del admin.
# Con APPLY=true falla si no puede decidir un image_tag (no se crea nada a ciegas).
if [ "$ACCION" = "apply" ]; then export APPLY=true; else export APPLY=false; fi
VARS_OUT="$TMP/vars-${AMBIENTE}.txt"
GITHUB_OUTPUT="$VARS_OUT" ./scripts/ci/preparar-variables.sh "$AMBIENTE"
BUCKET="$(grep '^bucket=' "$VARS_OUT" | cut -d= -f2)"
IMAGE_TAG="$(grep '^image_tag=' "$VARS_OUT" | cut -d= -f2)"
VAR_FILES=(-var-file="envs/${AMBIENTE}.tfvars" -var-file="$TMP/ci.auto.tfvars.json")

resumen_plan() { # $1 = nombre, $2 = archivo con la salida del plan
  {
    echo "#### $1"
    grep -E '^Plan:|^No changes|will be (created|destroyed|updated|replaced)|must be replaced' "$2" | sed 's/^/- /' || true
  } >> "$SUMMARY"
}

echo "### Terraform: ${AMBIENTE} → ${ACCION} (image_tag \`${IMAGE_TAG}\`)" >> "$SUMMARY"

# ---- global/ (repositorios de ECR y Lambda de seguridad): se comparten, se manejan solo desde dev.
if [ "$AMBIENTE" = "dev" ] && [ "$ACCION" != "destroy" ]; then
  (
    cd global
    export TF_DATA_DIR="$TMP/tf-data-global"
    # Mail de las alertas del escaneo de ECR (DEVOPS-46); vacío = sin suscripción.
    export TF_VAR_alert_email="${ALERT_EMAIL:-}"
    terraform init -reconfigure -backend-config=../backend/global.hcl -backend-config="bucket=${BUCKET}" >/dev/null
    terraform plan -no-color -lock-timeout=15m -out="$TMP/global.tfplan" | tee "$TMP/global-plan.txt"
    if [ "$ACCION" = "apply" ]; then
      terraform apply -no-color -lock-timeout=15m "$TMP/global.tfplan"
    fi
  )
  resumen_plan global "$TMP/global-plan.txt"
fi

# ---- El ambiente: cada uno con su propia key de state (backend/<amb>.hcl).
export TF_DATA_DIR="$TMP/tf-data-${AMBIENTE}"
terraform init -reconfigure -backend-config="backend/${AMBIENTE}.hcl" -backend-config="bucket=${BUCKET}" >/dev/null

if [ "$ACCION" = "destroy" ]; then
  # prod tiene deletion protection en el ALB y en RDS, y snapshot final.
  # Para un ambiente de Academy que se prende y se apaga, se desactivan con
  # un apply previo y recién ahí se destruye. En dev y test ya están en false.
  APAGAR=(-var=alb_deletion_protection=false -var=db_deletion_protection=false -var=db_skip_final_snapshot=true)
  if [ "$AMBIENTE" = "prod" ]; then
    echo "==> Quitando la protección contra borrado de prod"
    terraform apply -no-color -auto-approve -lock-timeout=15m "${VAR_FILES[@]}" "${APAGAR[@]}"
  fi
  echo "==> Destruyendo tero-${AMBIENTE}"
  terraform destroy -no-color -auto-approve -lock-timeout=15m "${VAR_FILES[@]}" "${APAGAR[@]}" | tee "$TMP/${AMBIENTE}-destroy.txt"
  { echo; grep -E '^Destroy complete' "$TMP/${AMBIENTE}-destroy.txt" || true; } >> "$SUMMARY"
  exit 0
fi

terraform plan -no-color -lock-timeout=15m "${VAR_FILES[@]}" -out="$TMP/${AMBIENTE}.tfplan" | tee "$TMP/${AMBIENTE}-plan.txt"
resumen_plan "$AMBIENTE" "$TMP/${AMBIENTE}-plan.txt"

if [ "$ACCION" = "plan" ]; then
  echo "Solo plan (no se aplica)." >> "$SUMMARY"
  exit 0
fi

# Se aplica el plan guardado: lo que se ve arriba es exactamente lo que se aplica.
terraform apply -no-color -lock-timeout=15m "$TMP/${AMBIENTE}.tfplan"
echo "Plan aplicado." >> "$SUMMARY"

# db-init: crea catalogdb, cartdb y la tabla cart_items si no existen.
# Sin esto, en un ambiente recién creado catalog y carts no arrancan.
echo "==> Inicializando la base (db-init)"
./scripts/inicializar-db.sh
echo "Base inicializada (db-init)." >> "$SUMMARY"

URL="$(terraform output -raw alb_url 2>/dev/null || true)"
[ -n "$URL" ] && echo "Tienda: ${URL}" >> "$SUMMARY"
exit 0
