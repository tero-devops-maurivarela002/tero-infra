#!/usr/bin/env bash
# DEVOPS-41: crea A MANO el bucket S3 donde Terraform guarda el state.
# Es la única pieza de infraestructura que no está en Terraform (la letra lo permite):
# Terraform necesita el bucket para guardar su state, así que no puede crearlo él mismo.
#
# Correr en AWS CloudShell dentro del lab de AWS Academy (o con credenciales del lab).
# Es idempotente: si el bucket ya existe, solo re-aplica la configuración.
set -euo pipefail

REGION="${AWS_REGION:-us-east-1}"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET="tero-tfstate-${ACCOUNT_ID}"
export AWS_DEFAULT_REGION="$REGION"

echo "Cuenta: ${ACCOUNT_ID}  Región: ${REGION}  Bucket: ${BUCKET}"

# 1. Crear el bucket (en us-east-1 no se pasa LocationConstraint)
if aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
  echo "1. El bucket ya existe, sigo con la configuración"
elif [ "$REGION" = "us-east-1" ]; then
  aws s3api create-bucket --bucket "$BUCKET"
  echo "1. Bucket creado"
else
  aws s3api create-bucket --bucket "$BUCKET" \
    --create-bucket-configuration LocationConstraint="$REGION"
  echo "1. Bucket creado"
fi

# 2. Versionado: cada apply deja una versión nueva del state y se puede volver atrás
aws s3api put-bucket-versioning --bucket "$BUCKET" \
  --versioning-configuration Status=Enabled
echo "2. Versionado activado"

# 3. Cifrado en reposo por defecto (el state puede tener datos sensibles)
aws s3api put-bucket-encryption --bucket "$BUCKET" \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"},
      "BucketKeyEnabled": true
    }]
  }'
echo "3. Cifrado SSE-S3 activado"

# 4. Bloquear todo acceso público
aws s3api put-public-access-block --bucket "$BUCKET" \
  --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
echo "4. Acceso público bloqueado"

# 5. Rechazar cualquier acceso que no sea por HTTPS
aws s3api put-bucket-policy --bucket "$BUCKET" --policy "{
  \"Version\": \"2012-10-17\",
  \"Statement\": [{
    \"Sid\": \"SoloHTTPS\",
    \"Effect\": \"Deny\",
    \"Principal\": \"*\",
    \"Action\": \"s3:*\",
    \"Resource\": [\"arn:aws:s3:::${BUCKET}\", \"arn:aws:s3:::${BUCKET}/*\"],
    \"Condition\": {\"Bool\": {\"aws:SecureTransport\": \"false\"}}
  }]
}"
echo "5. Política solo-HTTPS aplicada"

# 6. Borrar versiones viejas del state después de 90 días (que no crezca para siempre)
aws s3api put-bucket-lifecycle-configuration --bucket "$BUCKET" \
  --lifecycle-configuration '{
    "Rules": [{
      "ID": "versiones-viejas-90-dias",
      "Status": "Enabled",
      "Filter": {},
      "NoncurrentVersionExpiration": {"NoncurrentDays": 90},
      "AbortIncompleteMultipartUpload": {"DaysAfterInitiation": 7}
    }]
  }'
echo "6. Ciclo de vida de versiones viejas configurado"

echo
echo "=== Verificación ==="
aws s3api get-bucket-versioning --bucket "$BUCKET" --output text
aws s3api get-bucket-encryption --bucket "$BUCKET" \
  --query 'ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault.SSEAlgorithm' --output text
aws s3api get-public-access-block --bucket "$BUCKET" \
  --query 'PublicAccessBlockConfiguration' --output text
echo
echo "Listo. Usalo en el init así:"
echo "  terraform init -backend-config=backend/dev.hcl -backend-config=\"bucket=${BUCKET}\""
