# Evidencias Sprint 4: observabilidad (DEVOPS-49, 50 y 51)

Ambiente: dev (`tero-dev`), 24/11/2026. Todo lo crea Terraform (`modules/monitoring`, PR #13).

## DEVOPS-49: dashboard `tero-dev-operacion`

![Dashboard](DEVOPS-49-dashboard.png)

Arriba, el estado de las 3 alarmas. Después: pedidos por minuto al ALB, latencia
p95/p99 con la línea del umbral de la alarma (1,5 s), errores 5xx y 4xx, tareas
sanas de la tienda (ui), CPU y memoria por servicio y tareas corriendo por
servicio (Container Insights). En la captura la alarma de disponibilidad está
en ALARM por la prueba de abajo.

## DEVOPS-50 y 51: alarma con aviso por mail y runbook

Se forzó la alarma de disponibilidad para probar la cadena completa
(CloudWatch → SNS `tero-dev-alertas` → mail), como indica el runbook
[alerta-disponibilidad.md](../../runbooks/alerta-disponibilidad.md#cómo-probarla-evidencia):

```bash
aws cloudwatch set-alarm-state --alarm-name tero-dev-disponibilidad \
  --state-value ALARM --state-reason "Prueba de la alarma (evidencia DEVOPS-50)"
```

**ALARM** (00:27:38 UTC). El mail trae la descripción con el link al runbook:

![Mail de ALARM](DEVOPS-50-mail-alarma.png)

**OK** (00:29:03 UTC). CloudWatch volvió a evaluar la métrica real (1 tarea
sana en los 2 últimos minutos) y la alarma se recuperó sola:

![Mail de OK](DEVOPS-50-mail-ok.png)

Las alarmas de errores 5xx y latencia p95 (DEVOPS-51) usan el mismo topic y se
ven en verde (OK) en el dashboard. A los mails se les recortó el pie con el link
de desuscripción.

## DEVOPS-28: ambientes test y prod, prod con aprobación manual

25/11/2026, merge de `develop` a `main` (PR #16). El pipeline aplicó test solo y
se frenó antes de tocar prod: el job `apply prod` usa el environment
`production`, que exige la aprobación de uno de los dos integrantes.

![Prod esperando aprobación](DEVOPS-28-prod-esperando-aprobacion.png)

La aprobación, con el comentario de por qué se aprueba (test ya estaba OK):

![Aprobación de prod](DEVOPS-28-aprobacion-prod.png)

## DEVOPS-49: dashboards de test y prod

Cada ambiente tiene su dashboard (`tero-<ambiente>-operacion`), creado por el
mismo módulo con sus propios umbrales.

Test recién creado: la alarma de disponibilidad está en ALARM porque las tareas
todavía no tenían la imagen desplegada (la alarma trata "sin datos" como caída,
a propósito):

![Dashboard de test recién creado](DEVOPS-49-dashboard-test-recien-creado.png)

Test después del deploy de tero-app, con las 3 alarmas en OK:

![Dashboard de test](DEVOPS-49-dashboard-test.png)

Prod, con 2 tareas por servicio:

![Dashboard de prod](DEVOPS-49-dashboard-prod.png)
