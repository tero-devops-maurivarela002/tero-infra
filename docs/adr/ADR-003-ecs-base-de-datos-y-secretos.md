# ADR-003: Cómputo, base de datos, descubrimiento de servicios y secretos

- **Estado:** Aceptado
- **Fecha:** 18/11/2026
- **Decisores:** Mauricio Varela
- **Tarea relacionada:** DEVOPS-43

## Contexto

Tero tiene 6 microservicios (catalog, carts, orders, checkout, ui y admin), una base PostgreSQL con 3 bases (`orders`, `catalogdb`, `cartdb`) y un Redis. Hoy se levantan con `docker compose`, donde los servicios se encuentran por nombre (`http://catalog:8080`) y las contraseñas vienen de un `.env`.

Condiciones: AWS Academy (sin roles IAM propios, solo `LabRole`), presupuesto chico, tres ambientes y la letra pide que los secretos no queden en texto plano ni en el repo ni en el state de Terraform.

## Decisión

1. **ECS Fargate** con un módulo reutilizable `modules/ecs-service` instanciado 6 veces con `for_each`. Cada servicio tiene su task definition, su log group `/tero/<entorno>/<servicio>` y su servicio ECS con *deployment circuit breaker* y rollback automático. Las tareas corren en subnets privadas, sin IP pública.
2. **ALB** público con dos listeners: `:80` → ui (la tienda) y `:8081` → admin, este último limitado por security group a las IPs de `admin_allowed_cidrs`.
3. **Descubrimiento de servicios con un ALB interno:** el mismo módulo `modules/alb` se instancia una segunda vez como ALB interno (en subnets privadas), con un puerto por servicio de backend: catalog `:8001`, carts `:8002`, orders `:8003` y checkout `:8004`. ui y checkout reciben esas URLs por variables de entorno (lo que en compose era `http://catalog:8080`). El ALB además balancea entre tareas y saca de rotación las que fallan el health check.
4. **RDS PostgreSQL 16** y **ElastiCache Redis** en subnets privadas, cifrados en reposo. Redis también cifra en tránsito (`rediss://`, que checkout ya soporta). En prod: Multi-AZ, réplica de Redis, 2 tareas por servicio y protección contra borrado (ver `envs/prod.tfvars`).
5. **Secretos fuera del state:** las contraseñas (base y admin) se generan con recursos `ephemeral "random_password"` y se escriben con atributos *write-only* (`password_wo`, `secret_string_wo`). Terraform las manda a AWS pero no las guarda ni en el plan ni en el state. Quedan en **Secrets Manager** y las tareas las reciben con `secrets = [{ name, valueFrom }]`, así que tampoco aparecen en la task definition.
6. **Rotación controlada:** subir `db_password_version` o `admin_secret_version` en 1 genera una contraseña nueva y la cambia en RDS y en Secrets Manager en el mismo `apply`. Las tareas leen el secreto al arrancar: la variable `SECRETS_VERSION` cambia con la versión, así que ECS las reemplaza en el mismo apply (runbook en [docs/runbooks/rotacion-de-secretos.md](../runbooks/rotacion-de-secretos.md), DEVOPS-35).
7. **Inicialización de la base** con una tarea ECS de una sola vez (`db-init`, imagen oficial de PostgreSQL desde ECR Public) que se lanza con `scripts/inicializar-db.sh`. Es idempotente.

## Alternativas consideradas

- **`manage_master_user_password = true` en RDS:** RDS genera y guarda la contraseña en Secrets Manager. Lo descartamos porque la **rota sola cada 7 días** y las tareas que ya están corriendo quedarían con la contraseña vieja hasta el próximo deploy. Con write-only controlamos cuándo se rota.
- **Cloud Map (DNS privado `<servicio>.<entorno>.tero.local`) o ECS Service Connect:** era la primera opción, sin costo extra. **AWS Academy no lo permite**: el primer `apply` falló con `AccessDeniedException` en `servicediscovery:CreatePrivateDnsNamespace`, y Service Connect también necesita un namespace de Cloud Map. El ALB interno cuesta ~USD 0,55 por día más.
- **Base y Redis como contenedores en ECS:** más barato, pero sin backups ni Multi-AZ, y los datos se pierden si la tarea se reinicia.
- **Un ALB por servicio o rutas por path:** el admin no soporta servir desde un subpath, y un ALB por servicio duplica el costo.

## Consecuencias

- **TLS hacia RDS:** catalog y orders conectan con `sslmode=disable` fijo en el código, así que el parámetro `rds.force_ssl` queda en 0 (`db_force_ssl = false`). El tráfico no sale de las subnets privadas y el security group solo acepta a los servicios, pero viaja sin cifrar dentro de la VPC. Queda como hallazgo para el informe de seguridad (DEVOPS-37), con remediación: leer `sslmode` de una variable de entorno en catalog y orders y pasar `db_force_ssl = true`.
- Las apps usan el usuario maestro de la base (igual que en compose). Lo correcto sería un usuario por servicio con permisos mínimos; queda como mejora.
- Si la instancia RDS se recrea (por ejemplo, al cambiar algo que fuerza reemplazo), hay que subir `db_password_version` en el mismo apply para que la contraseña nueva quede también en Secrets Manager.
- Costo aproximado de dev encendido: NAT, ALB, RDS y Redis, unos USD 2,5 por día. Conviene `terraform destroy` del ambiente cuando no se usa por varios días.
