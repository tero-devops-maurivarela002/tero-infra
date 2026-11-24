# Runbook: alarmas de errores y de latencia (`tero-<amb>-errores-5xx`, `tero-<amb>-latencia-p95`)

- **Tarea:** DEVOPS-51
- **Definidas en:** [`modules/monitoring/main.tf`](../../modules/monitoring/main.tf)
- **Dashboard:** `tero-<amb>-operacion` (output `dashboard_url`)

## Qué significan

| | Errores (`errores-5xx`) | Rendimiento (`latencia-p95`) |
|---|---|---|
| **Trigger** | Más del **5 %** de los pedidos al ALB público terminan en **5xx** (de los servicios + del ALB), en **3 de los últimos 5 minutos**. Solo cuenta si hubo **al menos 10 pedidos** en el minuto. | `TargetResponseTime` **p95 > 1,5 s** en **3 de los últimos 5 minutos**. |
| **Síntoma para el usuario** | Páginas o acciones que fallan (no carga el catálogo, no se puede comprar). | La tienda anda, pero lenta. |
| **Severidad** | Alta | Media |
| **Aviso** | Mail por SNS (`tero-<amb>-alertas`) al entrar en ALARM y al volver a OK. | Igual. |

**Por qué estos umbrales:** con poco tráfico (Academy), un único error haría
saltar una alarma de porcentaje; por eso el mínimo de 10 pedidos. "3 de 5"
evita que un pico de un minuto (por ejemplo, un deploy) dispare la alarma
(*flapping*). 1,5 s de p95 es más del doble de lo normal: en dev el
promedio de Newman es ~100 ms.

## Qué hacer (en orden)

1. **Mirar el dashboard** `tero-<amb>-operacion`: ¿desde cuándo? ¿Coincide con
   un deploy (ver Actions de tero-app)? ¿Subieron los pedidos (carga) o la CPU
   o memoria de algún servicio?
2. **Encontrar qué servicio falla.** La tienda (ui) reenvía `/api/*` a los
   backends por el ALB interno. Logs Insights sobre los log groups
   `/tero/<amb>/*` (consultas de DEVOPS-48):
   ```
   fields @timestamp, service, method, path, status, duration_ms
   | filter status >= 500
   | stats count() by service, path
   | sort count() desc
   ```
   Para latencia, lo mismo ordenando por `duration_ms`:
   ```
   fields service, path, duration_ms
   | stats pct(duration_ms, 95) as p95, count() by service, path
   | sort p95 desc
   ```
3. **Según lo que muestre:**

| Lo que ves | Causa probable | Acción |
|---|---|---|
| Empezó justo después de un deploy | Bug en la versión nueva | **Rollback**: `./scripts/desplegar-ecs.sh <amb> <sha-anterior>` (tero-app), o revertir el PR |
| 5xx solo en `/api/catalog`, `/api/carts` u `/api/orders`, y errores de conexión a la base en los logs | RDS caída, llena, o contraseña rotada sin reiniciar tareas | Estado de RDS en la consola; si fue una rotación: [rotacion-de-secretos.md](rotacion-de-secretos.md) |
| 5xx solo en `/api/checkout` | Redis o el servicio orders | Logs de checkout y orders; estado de ElastiCache |
| 502/504 del ALB, un backend con 0 tareas | El servicio se cayó | Ver [alerta-disponibilidad.md](alerta-disponibilidad.md), paso 2, con ese servicio |
| Latencia alta y CPU cerca del 100 % en un servicio | Falta capacidad (0,25 vCPU por tarea) | Subir `service_desired_count` o `service_cpu` en `envs/<amb>.tfvars` por PR; a corto plazo `aws ecs update-service --desired-count 2` |
| Latencia alta solo en rutas con base de datos | Consultas lentas o RDS saturada | Métricas de RDS (CPU, conexiones) |

4. **Cerrar:** las alarmas vuelven solas a **OK** cuando la condición deja de
   cumplirse (llega el mail de OK). Anotar causa, acción y si hace falta un
   cambio permanente (PR).

## Cómo probarlas (evidencia)

**Errores:** apagar un backend y generar tráfico contra una ruta que lo usa:
```bash
aws ecs update-service --cluster tero-dev --service catalog --desired-count 0
ALB=http://<alb-de-dev>
for i in $(seq 1 600); do curl -s -o /dev/null "$ALB/api/catalog/products"; sleep 0.5; done
# en 3 a 5 minutos pasa a ALARM; después:
aws ecs update-service --cluster tero-dev --service catalog --desired-count 1
```
**Latencia, o solo la cadena de aviso:**
```bash
aws cloudwatch set-alarm-state --alarm-name tero-dev-latencia-p95 \
  --state-value ALARM --state-reason "Prueba del runbook"
```
