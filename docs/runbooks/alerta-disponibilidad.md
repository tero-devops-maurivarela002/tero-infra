# Runbook: alarma de disponibilidad (`tero-<amb>-disponibilidad`)

- **Tarea:** DEVOPS-50
- **Definida en:** [`modules/monitoring/main.tf`](../../modules/monitoring/main.tf)
- **Dashboard:** `tero-<amb>-operacion` (output `dashboard_url`)

## Qué significa

| | |
|---|---|
| **Trigger** | `HealthyHostCount` (mínimo) del target group de **ui** en el ALB público **< 1** durante **2 minutos seguidos**. Sin datos también cuenta como alarma. |
| **Síntoma para el usuario** | La tienda no carga: el ALB responde **503 Service Unavailable**. |
| **Severidad** | Alta: la tienda está caída. |
| **Aviso** | Mail por SNS (`tero-<amb>-alertas`) al entrar en ALARM y al volver a OK. |

Es una alarma de **síntoma** (lo que ve el usuario), no de causa: no dice
*por qué* no hay tareas sanas. Eso se averigua con los pasos de abajo.

## Qué hacer (en orden)

1. **Confirmar el síntoma** (1 minuto):
   ```bash
   curl -s -o /dev/null -w '%{http_code}\n' http://<alb>/health   # 503 = confirmado
   ```
2. **Ver el estado del servicio ui y sus últimos eventos:**
   ```bash
   aws ecs describe-services --cluster tero-<amb> --services ui \
     --query 'services[0].[runningCount,desiredCount,deployments[0].rolloutState]' --output text
   aws ecs describe-services --cluster tero-<amb> --services ui \
     --query 'services[0].events[0:5].message' --output text
   ```
3. **Según lo que muestre:**

| Lo que ves | Causa probable | Acción |
|---|---|---|
| `desiredCount` = 0 | Alguien bajó el servicio (o es la prueba de la alarma) | `aws ecs update-service --cluster tero-<amb> --service ui --desired-count 1` (2 en prod) |
| Tareas que arrancan y se caen (`essential container exited`) | Error de la aplicación o de configuración en la versión nueva | Ver logs (paso 4). Si vino con un deploy: **rollback** al SHA anterior: `./scripts/desplegar-ecs.sh <amb> <sha-anterior>` (tero-app) |
| `unhealthy in target group` | La app arranca pero `/health` no responde 200 | Logs (paso 4); revisar puerto 8080 y health check del target group |
| `CannotPullContainerError` | La imagen no existe en ECR o se venció la sesión de Academy | Verificar el tag en ECR; [prender-el-lab.md](prender-el-lab.md) |
| `deployments[0].rolloutState` = `FAILED` | El circuit breaker hizo rollback | La versión anterior debería estar sirviendo: ver por qué falló la nueva antes de reintentar |
| Todo sano pero la alarma sigue | El ALB o el target group no reportan (ambiente recién recreado) | Esperar 2 a 3 minutos; si sigue, revisar el listener :80 del ALB |

4. **Logs del servicio** (JSON, DEVOPS-48):
   ```bash
   aws logs tail /tero/<amb>/ui --since 15m --format short
   ```
5. **Cerrar:** la alarma vuelve sola a **OK** cuando hay al menos 1 tarea sana
   2 minutos seguidos (llega el mail de OK). Anotar qué pasó y qué se hizo.

## Cómo probarla (evidencia)

En dev, bajar la tienda y volverla a subir:
```bash
aws ecs update-service --cluster tero-dev --service ui --desired-count 0
# ~3 minutos: la alarma pasa a ALARM y llega el mail
aws ecs update-service --cluster tero-dev --service ui --desired-count 1
# ~3 minutos más: vuelve a OK
```
Para probar solo la cadena de aviso (SNS y mail), sin tocar el servicio:
```bash
aws cloudwatch set-alarm-state --alarm-name tero-dev-disponibilidad \
  --state-value ALARM --state-reason "Prueba del runbook"
```
