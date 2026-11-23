#!/usr/bin/env bash
# Prepara lo que el pipeline de Terraform necesita y NO está en el repo:
#   - bucket: el nombre del bucket del state (lleva el número de cuenta).
#   - image_tag: qué versión de tero-app está desplegada. El CD de tero-app
#     (DEVOPS-27) cambia las imágenes de los servicios; si Terraform usara otro
#     SHA, los volvería para atrás. Por eso se toma el de la última revisión.
#   - admin_allowed_cidrs: las IPs que pueden entrar al admin. Vienen del secret
#     ADMIN_ALLOWED_CIDRS (repo público: la IP no se versiona) y se enmascaran
#     para que no aparezcan en los logs del plan.
# Deja un archivo $RUNNER_TEMP/ci.auto.tfvars.json que se pasa con -var-file.
set -euo pipefail

ENVIRONMENT="${1:?Falta el ambiente}"
REGION="${AWS_REGION:-us-east-1}"
OUT="${RUNNER_TEMP:-/tmp}/ci.auto.tfvars.json"

account="$(aws sts get-caller-identity --query Account --output text)"
bucket="tero-tfstate-${account}"

# 1. image_tag: el que pidieron a mano > el que corre en el ambiente.
image_tag="${INPUT_IMAGE_TAG:-}"
if [ -z "$image_tag" ]; then
  # Se toma la ÚLTIMA revisión registrada de la familia (no la que está
  # corriendo): el CD de tero-app registra la revisión nueva apenas arranca,
  # así que si un apply coincide con un deploy en curso, Terraform usa la
  # versión que se está desplegando y no vuelve los servicios a la anterior.
  image="$(aws ecs describe-task-definition --region "$REGION" \
            --task-definition "tero-${ENVIRONMENT}-ui" \
            --query 'taskDefinition.containerDefinitions[0].image' --output text 2>/dev/null || true)"
  if [ -n "$image" ] && [ "$image" != "None" ]; then
    image_tag="${image##*:}"
    echo "image_tag tomado de la última revisión de tero-${ENVIRONMENT}-ui: ${image_tag}"
  fi
fi
if [ -z "$image_tag" ]; then
  if [ "${APPLY:-false}" = "true" ]; then
    echo "::error::tero-${ENVIRONMENT} no está levantado: corré el workflow a mano con image_tag (un SHA de develop de tero-app)."
    exit 1
  fi
  # Solo para mostrar el plan en un PR cuando el ambiente está apagado.
  image_tag="ambiente-apagado"
  echo "::warning::tero-${ENVIRONMENT} no está levantado: el plan usa un image_tag de relleno (no se aplica)."
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

jq -n --arg tag "$image_tag" --argjson cidrs "$cidrs" \
  '{image_tag: $tag, admin_allowed_cidrs: $cidrs}' > "$OUT"

{
  echo "bucket=${bucket}"
  echo "image_tag=${image_tag}"
} >> "${GITHUB_OUTPUT:-/dev/null}"
