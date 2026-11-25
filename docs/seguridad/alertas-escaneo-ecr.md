# Alertas del escaneo de imágenes de ECR (DEVOPS-46)

- **Código:** [`global/seguridad.tf`](../../global/seguridad.tf) y
  [`global/lambda/alertas_escaneo_ecr/handler.py`](../../global/lambda/alertas_escaneo_ecr/handler.py)
- **Relacionado:** Trivy en el pipeline de tero-app (DEVOPS-32 y 33), [checkov.md](checkov.md)

## Qué hace

```
push de una imagen a ECR (tero/<servicio>:<sha>)
  └─► ECR la escanea (escaneo básico, scan_on_push = true)
        └─► evento "ECR Image Scan" ─► regla de EventBridge tero-escaneo-ecr
              └─► Lambda tero-alertas-escaneo-ecr
                    ├─ ¿hay CRITICAL o HIGH? no ─► solo log
                    └─ sí ─► SNS tero-seguridad ─► mail
```

El mail dice qué imagen es (repositorio, tag = SHA de tero-app y digest), la
cantidad de vulnerabilidades por severidad, las primeras 10 CVE (las CRITICAL
primero) con el paquete y la versión, y el link al resultado en la consola.

## Por qué, si ya está Trivy

Trivy (en el CI de tero-app) es el **gate**: bloquea la imagen antes de
publicarla. ECR es la **segunda opinión**, con otra base de vulnerabilidades,
y sobre la imagen exacta que se va a promover a test y prod. Si Trivy deja
pasar algo (o se publica una CVE nueva entre el build y el escaneo), avisa.

## Decisiones

- **En `global/`**, junto a los repositorios: la imagen se escanea una sola
  vez, cuando se publica, y es la misma que después llega a test y prod.
- **Topic propio** (`tero-seguridad`), separado de las alarmas de operación de
  cada ambiente: son avisos de otro tipo y de otro dueño (seguridad).
  Cifrado con la clave de AWS (`alias/aws/sns`).
- **Severidades configurables** (`scan_alert_severities`, por defecto
  CRITICAL y HIGH), las mismas que corta Trivy.
- **La Lambda usa LabRole**: en Academy no se pueden crear roles.
- **Si no puede leer el detalle de las CVE, avisa igual**, con los conteos del
  evento: el aviso importa más que el detalle.

Excepciones de Checkov de la Lambda (todas en el código con su motivo):

| Regla | Por qué no |
|---|---|
| CKV_AWS_117 (VPC) | No usa nada de la VPC. Dentro de una VPC necesitaría NAT o endpoints para llegar a ECR y SNS. |
| CKV_AWS_116 (DLQ) | La llama EventBridge de forma asíncrona, y ya reintenta. Si un aviso se pierde, el resultado sigue en ECR. |
| CKV_AWS_115 (concurrencia reservada) | En Academy el límite de la cuenta es bajo; reservar puede hacer fallar el apply. |
| CKV_AWS_173 (KMS para variables) | Las variables no tienen secretos (ARN del topic y severidades). |
| CKV_AWS_272 (code signing) | Necesita AWS Signer. El código solo lo despliega este pipeline, que pasa por PR. |
| CKV_AWS_50 (X-Ray) | Necesita permisos de X-Ray que LabRole puede no tener. |

## Qué hacer cuando llega el aviso

1. Abrir el link del mail y ver las CVE: paquete, versión y versión corregida.
2. Si es de la **imagen base** (por ejemplo `alpine` o `distroless`):
   actualizar el `FROM` en el Dockerfile del servicio en tero-app.
3. Si es de una **dependencia** del servicio (`go.mod`, `package.json`,
   `pom.xml`): subir la versión.
4. Si no hay versión corregida o no aplica: justificarlo en `.trivyignore` de
   tero-app con la CVE y el motivo, como el resto de las excepciones.
5. Esa imagen **no se promueve** a test ni a prod hasta resolverlo.

## Cómo probarlo (evidencia)

Las imágenes de Tero pasan Trivy, así que no deberían disparar el aviso. Para
probar la cadena completa se sube una imagen vieja a un repositorio
**temporal** `tero/prueba-escaneo` (la regla escucha `tero/*`), y después se
borra. No se usa un repositorio de un servicio para no mezclar una imagen
vulnerable con las que se despliegan. En CloudShell:

```bash
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
REG=$ACCOUNT.dkr.ecr.us-east-1.amazonaws.com
aws ecr create-repository --repository-name tero/prueba-escaneo \
  --image-scanning-configuration scanOnPush=true >/dev/null
aws ecr get-login-password | docker login --username AWS --password-stdin $REG
docker pull python:3.7-slim-buster          # imagen vieja, con CVE conocidas
docker tag python:3.7-slim-buster $REG/tero/prueba-escaneo:vieja
docker push $REG/tero/prueba-escaneo:vieja
```

En 1 o 2 minutos llega el mail. Para ver qué hizo la Lambda:

```bash
aws logs tail /aws/lambda/tero-alertas-escaneo-ecr --since 10m
```

Y al final, borrar el repositorio de prueba:

```bash
aws ecr delete-repository --repository-name tero/prueba-escaneo --force
```

Antes hay que confirmar la suscripción: después del primer apply llega un mail
de AWS Notifications para el topic `tero-seguridad` (**Confirm subscription**).
