#!/usr/bin/env bash
# DEVOPS-43: crea las bases catalogdb y cartdb y la tabla cart_items en RDS.
# Corre la tarea ECS "db-init" (definida en db-init.tf) dentro de la VPC,
# porque RDS no es accesible desde afuera. Es idempotente.
#
# Uso (desde la raíz de tero-infra, después de terraform apply):
#   ./scripts/inicializar-db.sh
set -euo pipefail

out() { terraform output -raw "$1"; }

CLUSTER=$(out ecs_cluster_name)
TASK_DEF=$(out db_init_task_definition)
SG=$(out services_security_group_id)
SUBNETS=$(terraform output -json private_subnet_ids | tr -d '[]" \n')
ENTORNO=$(out environment)

echo "Corriendo $TASK_DEF en el cluster $CLUSTER..."
TASK_ARN=$(aws ecs run-task \
  --cluster "$CLUSTER" \
  --task-definition "$TASK_DEF" \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[$SUBNETS],securityGroups=[$SG],assignPublicIp=DISABLED}" \
  --query 'tasks[0].taskArn' --output text)

echo "Tarea: $TASK_ARN"
echo "Esperando a que termine (1 o 2 minutos)..."
aws ecs wait tasks-stopped --cluster "$CLUSTER" --tasks "$TASK_ARN"

EXIT_CODE=$(aws ecs describe-tasks --cluster "$CLUSTER" --tasks "$TASK_ARN" \
  --query 'tasks[0].containers[0].exitCode' --output text)

echo
echo "=== Logs de db-init ==="
aws logs tail "/tero/${ENTORNO}/db-init" --since 15m --format short || true

if [ "$EXIT_CODE" = "0" ]; then
  echo "✅ Base inicializada"
else
  echo "❌ db-init terminó con código $EXIT_CODE"
  aws ecs describe-tasks --cluster "$CLUSTER" --tasks "$TASK_ARN" \
    --query 'tasks[0].{motivo:stoppedReason,contenedor:containers[0].reason}' --output table
  exit 1
fi
