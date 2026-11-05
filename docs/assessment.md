# Assessment de Tero (tarea DEVOPS-21)

> Es el punto de partida: qué hay hoy en el repo, antes de cambiar nada. El análisis (secciones 1 a 5) sale de leer el código en el commit `56fd8cb` (tag `baseline`) de `tero-devops-maurivarela002/tero-app`. Las mediciones de la sección 6 se hicieron ejecutando `docker compose` sobre ese mismo commit.

## 1. Resumen

- El repo tiene un solo commit (`chore: initial commit`, 13/10/2026), por lo que **no hay historial anterior con secretos**. Todos los secretos están en los archivos actuales, es decir, en el propio `baseline`.
- Son **6 servicios** más PostgreSQL y Redis, en 3 lenguajes (Go, Python y TypeScript).
- Los 6 servicios ya tienen `/health`. Tres exponen métricas de Prometheus.
- **No hay** tests, CI, linter, `.gitignore`, `.dockerignore` ni `.env`.
- Los 6 Dockerfiles son de una sola etapa, usan imágenes base completas y corren como root.

## 2. Servicios

| Servicio | Lenguaje | Puerto interno | Puerto publicado en el host | Almacenamiento | `/health` | Métricas Prometheus |
|---|---|---|---|---|---|---|
| `ui` | TypeScript, Express (Node 22) | 8080 | 8080 | n/a | Sí | No encontré |
| `catalog` | Go 1.24, Gin | 8080 | ninguno | PostgreSQL (`catalogdb`) | Sí | Sí (`go-gin-prometheus`) |
| `carts` | Python 3.12, FastAPI | 8080 | ninguno | PostgreSQL (`cartdb`) | Sí | Sí (`/metrics`, instrumentator) |
| `checkout` | TypeScript, NestJS | 8080 | ninguno | Redis | Sí | No encontré |
| `orders` | Go 1.24, Gin | 8080 | ninguno | PostgreSQL (`orders`) | Sí | Sí (`go-gin-prometheus`) |
| `admin` | TypeScript, Express | 8080 | 8081 | PostgreSQL directo (`catalogdb` y `orders`) | Sí | No encontré |
| `db` | PostgreSQL 16 | 5432 | **5433** | n/a | `pg_isready` en el compose | n/a |
| `redis` | Redis 7 | 6379 | **6379** | n/a | No | n/a |

Cómo se comunican (según el compose y el README): `ui` hace de proxy a `catalog`, `carts`, `checkout` y `orders`. `checkout` llama a `orders` y guarda sesión en Redis. Cada servicio se encuentra por **nombre DNS** (`http://catalog:8080`, etc.), configurado por variables de entorno `RETAIL_*`.

Otros datos útiles:
- `catalog` y `carts` usan memoria si no se les indica un proveedor (`in-memory` por defecto). En el compose están configurados con `postgres`.
- `carts` tiene además código para DynamoDB (`dynamodb_service.py` importa `boto3`), pero `boto3` **no está en `requirements.txt`**. A verificar si se importa solo al usarlo; si no, el servicio podría fallar al arrancar fuera de memoria o Postgres.
- `catalog` y `carts` tienen un endpoint `/topology`.

## 3. Observaciones del auditor, contra lo que hay

### A. Contraseñas en el repo (confirmado)

| Dónde | Qué |
|---|---|
| `docker-compose.yml` | `retailpassword` repetida en 5 variables (DB, catalog, carts, orders, admin) |
| `docker-compose.yml` | `ADMIN_PASSWORD: admin` y `ADMIN_JWT_SECRET: change-me-in-production` |
| `src/admin/src/app.ts` (líneas 12, 14 y 18) | los mismos valores como **fallback en el código**: `'change-me-in-production'`, `'admin'`, `'retailpassword'` |
| `README.md` | documenta los valores por defecto, incluida `admin` / `admin` |

Además, los 3 servicios de datos y `admin` se conectan con el **mismo usuario** (`retail_user`), que tiene `GRANT ALL` sobre las 3 bases (`init-db.sql`). Es una violación del mínimo privilegio.

### B. Imágenes y root (confirmado)

Los 6 Dockerfiles siguen el mismo patrón: `FROM <imagen completa>`, `COPY . .`, instalar, compilar y ejecutar en la misma imagen.

| Servicio | Imagen base | Problemas |
|---|---|---|
| `ui`, `admin`, `checkout` | `node:22` | etapa única, incluye `devDependencies` y compilador, root |
| `carts` | `python:3.12` | etapa única, root |
| `catalog`, `orders` | `golang:1.24` | el binario final queda dentro de la imagen del compilador de Go, root |

En ninguno hay `USER`, `.dockerignore` ni `HEALTHCHECK`. Las etiquetas (`node:22`, `golang:1.24`) no están fijadas a una versión exacta.

### C. Puertos publicados (confirmado)

`db` en `5433:5432` y `redis` en `6379:6379`. El compose también publica `ui` (8080) y `admin` (8081), que en la nube deben quedar detrás de un balanceador.

### D. Sin tests ni análisis (confirmado)

No hay archivos de test, configuración de linters ni pipelines. Tampoco hay `.gitignore`, así que nada impide subir un `.env` por accidente.

### E. Versión y despliegue repetible

No hay tags de imagen ni versionado: el compose usa `build:` local. Todo se resuelve más adelante con tags de imagen por SHA de git y pipelines.

### F. Métricas

Tres servicios ya exponen Prometheus: `catalog`, `carts` y `orders`. `ui`, `admin` y `checkout` no. Los logs de `checkout` salen en texto plano (clase `Logger` de NestJS), no en JSON, y en `ui` y `admin` solo vi `console.log` (no revisé si registran cada pedido). Para el requisito de logs estructurados hay que decidir cómo cubrirlo (ver sección 5).

## 4. Otros hallazgos

1. **Endpoints `/chaos/*` en `catalog`** (sin autenticación): permiten inyectar latencia, forzar errores HTTP o marcar el servicio como no saludable. Sirven para probar alertas en la defensa, pero **no deberían estar accesibles desde afuera** en Prod. Conviene que el balanceador solo enrute a `ui`.
2. **`admin` con sesión por JWT en cookie**, firmada con un secreto que hoy es fijo. Mover el secreto a Secrets Manager.
3. **`admin` accede directo a las bases** (`catalogdb` y `orders`), saltándose a los servicios. En Prod conviene exponerlo solo de forma restringida (por ejemplo, por IP o detrás de un listener separado).
4. Todos los servicios escuchan en el **puerto 8080**. En ECS Fargate cada tarea tiene su propia IP, así que no hay conflicto, pero hay que resolver cómo se descubren entre sí (nombres DNS como `catalog`, `carts`, `orders`, `checkout`). Opciones: ECS Service Connect, Cloud Map o un ALB interno.
5. `src/checkout/.yarn/releases/yarn-4.11.0.cjs` está versionado dentro del repo (es habitual en Yarn 4, solo hay que tenerlo en cuenta para el tamaño del zip y para `.dockerignore`).
6. Falta un contrato de configuración: no hay `.env.example`, y las variables están repartidas entre el compose, el README y valores por defecto en el código.

## 5. Qué implica para el plan

| Tarea del tablero | Impacto concreto |
|---|---|
| DEVOPS-30 Sacar secretos | Quitar los valores del compose y de `admin/src/app.ts` (que falle si falta la variable, sin fallback), crear `.env.example` y `.gitignore`, y rotar todo (aunque sean valores de ejemplo, el repo los publica) |
| DEVOPS-22 Dockerfiles | Multi-stage para Go (compilar y copiar el binario a `alpine` o `distroless`), para Node (build y luego solo `dist` más dependencias de producción) y para Python (venv y `slim`). Un `USER` no-root en todos |
| DEVOPS-23 `.dockerignore` | Excluir `.git`, `node_modules`, `.yarn/releases` y archivos locales |
| DEVOPS-24 compose | Quitar `ports:` de `db` y `redis`, y leer las credenciales desde `.env` |
| Observabilidad | Usar las métricas existentes (`catalog`, `carts` y `orders`), y para `ui`, `admin` y `checkout` quedarse con las métricas del ALB y Container Insights. Para logs estructurados, decidir entre cambiar el formato en los servicios o parsear en CloudWatch |
| Tests | Como no hay ninguno, el "par de tests" de la letra lo cubre una colección de Newman contra `/health` y el flujo de compra |
| CI en matrix | 6 servicios en 3 lenguajes: `go test`, `pytest` y `yarn`/`npm`. Ojo: no hay tests unitarios, así que esa etapa corre solo build y lint |

## 6. Mediciones antes de optimizar (línea base)

Medido el 04/11/2026 sobre `main` en el commit `56fd8cb` (tag `baseline`), con `docker compose up --build` y `docker images`, sin cambiar ningún archivo.

### Tamaño de las imágenes (antes)

| Servicio | Imagen base | Tamaño antes | Tamaño después |
|---|---|---|---|
| catalog | `golang:1.24` | 2.26 GB | _(completar en DEVOPS-22)_ |
| checkout | `node:22` | 2.03 GB | _(completar en DEVOPS-22)_ |
| orders | `golang:1.24` | 2.03 GB | _(completar en DEVOPS-22)_ |
| admin | `node:22` | 1.73 GB | _(completar en DEVOPS-22)_ |
| ui | `node:22` | 1.72 GB | _(completar en DEVOPS-22)_ |
| carts | `python:3.12` | 1.71 GB | _(completar en DEVOPS-22)_ |

Las 6 imágenes pesan entre 1.7 y 2.3 GB porque son de una sola etapa sobre imágenes base completas, e incluyen compiladores, `devDependencies` y el código fuente.

### Verificaciones

- [x] `docker compose up --build` levanta los 8 contenedores y la tienda responde en `localhost:8080`.
- [x] `carts` arranca sin `boto3` con el proveedor `postgres`. El flujo de carrito funciona (`POST /carts/{id}/items` devuelve 201 y `GET /carts/{id}` devuelve 200). El módulo de DynamoDB solo se usa si se configura ese proveedor.
- [ ] `gitleaks detect --source . --no-git` sobre los archivos actuales _(pendiente, se ejecuta en DEVOPS-31)_.
- [ ] `trivy fs .` y `trivy image` como línea base _(pendiente, se ejecutan en DEVOPS-32 y DEVOPS-33)_.

## 7. Qué sigue

Los hallazgos de las secciones 3 y 4 se atacan en este orden: DEVOPS-30 (secretos), DEVOPS-22 y DEVOPS-23 (Dockerfiles y `.dockerignore`), DEVOPS-24 (puertos de DB y Redis). La columna "después" de la tabla se completa al cerrar DEVOPS-22.
