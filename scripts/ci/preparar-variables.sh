#!/usr/bin/env bash
# Prepara lo que el pipeline de Terraform necesita y NO está en el repo:
#   - bucket: el nombre del bucket del state (lleva el número de cuenta).
#   - image_tag: qué versión de tero-app está desplegada. El CD de tero-app
#     (DEVOPS-27) cambia las imágenes de los servicios; si Terraform usara otro
#     SHA, los volvería para atrás. Por eso se toma el de la última revisión.
#   - admin_allowed_cidrs: las IPs que pueden entrar al admin. Vienen del secret
#     ADMIN_ALLOWED_CIDRS (repo público: la IP no se versiona) y se enmascaran
#     para que no aparezcan en los logs del plan.
#   - alert_email: a quién le llegan las alarmas (secret ALERT_EMAIL, opcional).
# Deja un archivo $RUNNER_TEMP/ci.auto.tfvars.json que se pasa con -var-file.
set -euo pipefail

ENVIRONMENT="${1:?Falta el ambiente}"
REGION="${AWS_REGION:-us-east-1}"
OUT="${RUNNER_TEMP:-/tmp}/ci.auto.tfvars.json"

account="$(aws sts get-caller-identity --query Account --output text)"
bucket="tero-tfstate-${account}"

# 1. image_tag, en este orden de preferencia:
#    a) el que pidieron a mano (INPUT_IMAGE_TAG);
#    b) el de la última revisión del propio ambiente (lo que ya corre ahí);
#    c) si el ambiente está apagado, el del ambiente ANTERIOR en la cadena de
#       promoción (test toma el de dev; prod el de test y si no el de dev):
#       un ambiente nuevo arranca con una versión que ya pasó por los anteriores;
#    d) para dev recién creado: la última imagen publicada en ECR (tero/ui).
# Se toma la ÚLTIMA revisión registrada de la familia (no la que está
# corriendo): el CD de tero-app registra la revisión nueva apenas arranca,
# así que si un apply coincide con un deploy en curso, Terraform usa la
# versión que se está desplegando y no vuelve los servicios a la anterior.
ultima_imagen() { # $1 = ambiente; imprime el tag o nada
  local image
  image="$(aws ecs describe-task-definition --region "$REGION"             --task-definition "tero-${1}-ui"             --query 'taskDefinition.containerDefinitions[0].image' --output text 2>/dev/null || true)"
  if [ -n "$image" ] && [ "$image" != "None" ]; then echo "${image##*:}"; fi
}

image_tag="${INPUT_IMAGE_TAG:-}"
[ -z "$image_tag" ] || echo "image_tag pedido a mano: ${image_tag}"

case "$ENVIRONMENT" in
  prod) cadena="prod test dev" ;;
  test) cadena="test dev" ;;
  *)    cadena="$ENVIRONMENT" ;;
esac
for amb in $cadena; do
  [ -z "$image_tag" ] || break
  image_tag="$(ultima_imagen "$amb")"
  [ -z "$image_tag" ] || echo "image_tag tomado de la última revisión de tero-${amb}-ui: ${image_tag}"
done

if [ -z "$image_tag" ]; then
  image_tag="$(aws ecr describe-images --region "$REGION" --repository-name tero/ui                 --query 'sort_by(imageDetails, &imagePushedAt)[-1].imageTags[0]'                 --output text 2>/dev/null || true)"
  if [ "$image_tag" = "None" ]; then image_tag=""; fi
  [ -z "$image_tag" ] || echo "image_tag tomado de la última imagen publicada en ECR (tero/ui): ${image_tag}"
fi

if [ -z "$image_tag" ]; then
  if [ "${APPLY:-false}" = "true" ]; then
    echo "::error::No hay ninguna versión de tero-app para desplegar: corré el workflow a mano con image_tag (un SHA de develop de tero-app)."
    exit 1
  fi
  # Solo para mostrar el plan en un PR cuando no hay nada levantado.
  image_tag="ambiente-apagado"
  echo "::warning::No hay ninguna versión de tero-app a mano: el plan usa un image_tag de relleno (no se aplica)."
fi

# 2. IPs del admin (opcional). Formato del secret: ["1.2.3.4/32"]
cidrs="${ADMIN_ALLOWED_CIDRS:-}"
[ -n "$cidrs" ] || cidrs='[]'
echo "$cidrs" | jq -e 'type == "array"' >/dev/null \
  || { echo "::error::ADMIN_ALLOWED_CIDRS tiene que ser una lista JSON, ej. [\"1.2.3.4/32\"]"; exit 1; }
for c in $(echo "$cidrs" | jq -r '.[]'); do
  echo "::add-mask::${c}"
  echo "::add-mask::${c%/*}"
done

# 3. Email de las alarmas (opcional, secret ALERT_EMAIL): dato personal, no se versiona.
alert_email="${ALERT_EMAIL:-}"
[ -z "$alert_email" ] || echo "::add-mask::${alert_email}"

jq -n --arg tag "$image_tag" --argjson cidrs "$cidrs" --arg email "$alert_email" \
  '{image_tag: $tag, admin_allowed_cidrs: $cidrs, alert_email: $email}' > "$OUT"

{
  echo "bucket=${bucket}"
  echo "image_tag=${image_tag}"
} >> "${GITHUB_OUTPUT:-/dev/null}"
