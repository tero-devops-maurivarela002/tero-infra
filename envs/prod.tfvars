environment = "prod"
aws_region  = "us-east-1"

# Red: un NAT por zona para que la caída de una zona no deje sin salida a la otra
vpc_cidr           = "10.30.0.0/16"
az_count           = 2
single_nat_gateway = false

# Panel admin: agregar la IP propia, por ejemplo ["190.64.x.x/32"] (curl ifconfig.me)
admin_allowed_cidrs     = []
alb_deletion_protection = true

# ECS: image_tag se pasa en cada apply con -var="image_tag=<sha>" (lo hace el CD)
service_desired_count = 2
service_cpu           = 256
service_memory        = 512
log_retention_days    = 14

# Base de datos y Redis
db_instance_class        = "db.t3.micro"
db_multi_az              = true
db_backup_retention_days = 7
db_deletion_protection   = true
db_skip_final_snapshot   = false
redis_node_type          = "cache.t3.micro"
redis_replicas           = 1
