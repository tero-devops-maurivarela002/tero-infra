# Checkov: análisis de seguridad de la infraestructura (DEVOPS-36)

[Checkov](https://www.checkov.io/) revisa el código de Terraform contra reglas
de buenas prácticas de seguridad (cifrado, exposición a internet, logs, etc.)
**antes** de crear nada en AWS. Corre en el job `checkov` del pipeline
([`.github/workflows/terraform.yml`](../../.github/workflows/terraform.yml)),
versión fija `3.4.5`, y es un **gate**: si aparece un hallazgo que no está
corregido ni justificado, el pipeline falla y no hay plan ni apply.

Los resultados se publican en *Security → Code scanning* (SARIF) y como
artefacto del run.

Para correrlo local: `checkov -d . --framework terraform --compact`

## Resultado del triage

Primera corrida: **142 controles OK y 52 fallidos**, de 22 reglas distintas.
Checkov cuenta por recurso: una regla que falla en los 6 listeners suma 6.
Después del triage quedan **0 fallidos**: 1 regla corregida y 21 reglas con
excepción justificada (52 excepciones, contadas por recurso).

### Corregidos

| Regla | Qué pedía | Cambio |
|---|---|---|
| CKV_AWS_394 | Fijar las zonas de disponibilidad | `aws_availability_zones` filtra por nombre (`us-east-1a/b/c`): si AWS agrega una zona, la red no cambia sola. |
| CKV_AWS_150 (ALB interno) | Deletion protection | El ALB interno ahora usa `alb_deletion_protection` igual que el público (true en prod). Sigue la excepción porque en dev/test es false a propósito. |

### Excepciones justificadas

Cada una está en el código, junto al recurso, como
`#checkov:skip=<regla>:<motivo>`, para que la justificación se revise en el
mismo PR que el cambio. Se agrupan por causa:

**1. Configuradas por ambiente (en prod están activas).** Checkov mira los
valores por defecto, no los `envs/*.tfvars`.

| Regla | Control | dev / test | prod |
|---|---|---|---|
| CKV_AWS_157 | RDS Multi-AZ | no | sí (`db_multi_az`) |
| CKV_AWS_293 | RDS deletion protection | no | sí |
| CKV2_AWS_50 | Redis Multi-AZ con failover | no | sí (`redis_replicas = 1`) |
| CKV_AWS_150 | ALB deletion protection | no | sí |

**2. Sin dominio propio no hay HTTPS.** AWS Academy no da un dominio, y sin
dominio no se puede emitir un certificado de ACM. Riesgo: el tráfico
cliente → ALB viaja sin cifrar. Mitigación: es un ambiente académico sin datos
reales; el ALB → servicios va por subnets privadas. Plan: con un dominio,
listener 443 + redirect 80→443 y se sacan estas excepciones.
CKV_AWS_2, CKV_AWS_103, CKV2_AWS_20, CKV_AWS_260, CKV_AWS_378.

**3. Limitaciones de AWS Academy (no se pueden crear roles de IAM).**

| Regla | Control | Por qué no / alternativa |
|---|---|---|
| CKV_AWS_249 | Execution role ≠ task role | Solo existe LabRole. |
| CKV2_AWS_57 | Rotación automática de secretos | Requiere una Lambda con rol propio. Rotación manual con runbook (DEVOPS-35). |
| CKV_AWS_118 | RDS enhanced monitoring | Requiere el rol `rds-monitoring-role`. Se usan métricas estándar de CloudWatch. |
| CKV2_AWS_11 | VPC flow logs | A CloudWatch requiere rol propio. Mejora planificada: flow logs a S3 (no necesita rol). |
| CKV2_AWS_28 | WAF en el ALB público | Costo fijo mensual; no habilitado en el lab. |
| CKV_AWS_50 | X-Ray en la Lambda de seguridad (DEVOPS-46) | Necesita permisos de X-Ray en LabRole; si faltan, falla la creación. La Lambda es de un solo paso y deja log estructurado. |
| CKV_AWS_115, CKV_AWS_116, CKV_AWS_117, CKV_AWS_173, CKV_AWS_272 | Lambda: concurrencia reservada, DLQ, VPC, KMS propio para variables, code signing | Concurrencia baja en Academy; EventBridge ya reintenta; no usa recursos de la VPC; las variables no tienen secretos; code signing necesita AWS Signer. Detalle en [alertas-escaneo-ecr.md](alertas-escaneo-ecr.md). |

**4. Costo / complejidad no justificada en este proyecto.**

| Regla | Control | Decisión |
|---|---|---|
| CKV_AWS_149, CKV_AWS_158, CKV_AWS_191 | Cifrado con KMS CMK (secretos, logs, Redis) | Todo **está cifrado**, con las claves administradas por AWS. Una CMK propia cuesta USD 1/mes por clave y agrega gestión de key policies. |
| CKV_AWS_338 | Retención de logs ≥ 1 año | Decidido en DEVOPS-47: 7 días dev/test, 14 prod. |
| CKV_AWS_91 | Access logs del ALB | Necesita bucket con política de ELB. Mejora planificada. |
| CKV_AWS_353 | RDS Performance Insights | No se usa en db.t3.micro de dev/test. |
| CKV_AWS_161 | RDS con autenticación IAM | Las apps usan usuario/contraseña de Secrets Manager; IAM auth requiere cambiar el código. |

**5. Hallazgos abiertos (riesgo aceptado temporalmente).**

| Regla | Control | Estado |
|---|---|---|
| CKV2_AWS_69 | RDS con TLS obligatorio | `rds.force_ssl = 0` porque catalog y orders se conectan con `sslmode=disable`. Se aborda en DEVOPS-37. |
| CKV_AWS_31 | Redis con AUTH token | TLS en tránsito **sí** está activo. Falta el token: hay que pasarlo a checkout en la URL (desde Secrets Manager). Acceso limitado al SG de servicios. |

**6. Falso positivo.** CKV2_AWS_5 (security group sin usar): los SGs se crean
en el módulo `network` y se asocian en otros módulos; Checkov no sigue esa
relación entre módulos.

## Cómo agregar una excepción

Solo con motivo, en el recurso y en el mismo PR:

```hcl
resource "aws_lb" "this" {
  #checkov:skip=CKV2_AWS_28:WAF tiene costo fijo y no está habilitado en AWS Academy
  ...
```

y sumarla a la tabla de arriba. Una excepción sin motivo no pasa la revisión.
