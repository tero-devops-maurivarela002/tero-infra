# Módulo `network`

Red de un ambiente de Tero: VPC, subnets públicas y privadas en 2 (o 3) zonas de disponibilidad, Internet Gateway, NAT Gateway, endpoint de S3 y los security groups de la cadena ALB → servicios → base de datos / Redis.

## Diagrama

```
                    Internet
                       │
               ┌───────▼────────┐
               │ Internet GW    │
┌──────────────┴────────────────┴───────────────── VPC 10.x.0.0/16 ──┐
│  Subnets públicas 10.x.0.0/24, 10.x.1.0/24                          │
│     ALB (sg-alb: 80 desde internet)      NAT Gateway               │
│        │                                     ▲                      │
│        ▼ 8080                                │ salida a internet    │
│  Subnets privadas 10.x.10.0/24, 10.x.11.0/24 │ (ECR, Secrets, Logs) │
│     Tareas ECS (sg-services: 8080 desde ALB y entre servicios) ─────┘
│        │ 5432                │ 6379                                 │
│        ▼                     ▼                                      │
│     RDS (sg-database)     ElastiCache (sg-redis)                   │
└─────────────────────────────────────────────────────────────────────┘
```

## Uso

```hcl
module "network" {
  source = "./modules/network"

  name               = "tero-dev"
  vpc_cidr           = "10.10.0.0/16"
  az_count           = 2
  single_nat_gateway = true
}
```

## Variables

| Variable | Default | Descripción |
|---|---|---|
| `name` | (obligatoria) | Prefijo de los nombres, por ejemplo `tero-dev`. |
| `vpc_cidr` | (obligatoria) | Rango de la VPC, /20 o más grande. |
| `az_count` | `2` | Zonas de disponibilidad (2 o 3). |
| `single_nat_gateway` | `true` | Un NAT compartido (`true`) o uno por zona (`false`). |
| `app_port` | `8080` | Puerto de los contenedores. |
| `postgres_port` | `5432` | Puerto de PostgreSQL. |
| `redis_port` | `6379` | Puerto de Redis. |

## Outputs

`vpc_id`, `vpc_cidr`, `availability_zones`, `public_subnet_ids`, `private_subnet_ids`, `nat_public_ips` y los IDs de los security groups `alb`, `services`, `database` y `redis` (ver `outputs.tf`, todos con `description`).

## Decisiones

- **Servicios en subnets privadas** y la base de datos y Redis solo aceptan tráfico desde el security group de los servicios: resuelve la observación C del assessment (DB y Redis publicados).
- **Reglas por security group, no por IP:** si una tarea cambia de IP, la regla sigue valiendo.
- **NAT Gateway y no solo endpoints:** los servicios necesitan ECR, Secrets Manager y CloudWatch Logs. Con endpoints de interfaz serían 4 endpoints × 2 zonas (~USD 58/mes) contra ~USD 33/mes de un NAT. Se suma el endpoint *gateway* de S3, que es gratis y saca del NAT la descarga de capas de las imágenes.
- **Un NAT en dev/test, uno por zona en prod:** en dev ahorramos; en prod, si se cae la zona del NAT, la otra zona sigue saliendo a internet.
- **El security group `default` queda sin reglas** para que nada lo use por accidente.
- **ALB por HTTP (80):** en AWS Academy no tenemos dominio propio para emitir un certificado en ACM. Es una excepción documentada para Checkov (DEVOPS-36).
