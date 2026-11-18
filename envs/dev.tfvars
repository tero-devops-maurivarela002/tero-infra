environment = "dev"
aws_region  = "us-east-1"

# Red
vpc_cidr           = "10.10.0.0/16"
az_count           = 2
single_nat_gateway = true

# Panel admin: agregar la IP propia, por ejemplo ["190.64.x.x/32"] (curl ifconfig.me)
admin_allowed_cidrs     = []
alb_deletion_protection = false

# ECS: image_tag se pasa en cada apply con -var="image_tag=<sha>" (lo hace el CD)
service_desired_count = 1
service_cpu           = 256
service_memory        = 512
log_retention_days    = 7

# Base de datos y Redis
db_instance_class        = "db.t3.micro"
db_multi_az              = false
db_backup_retention_days = 1
db_deletion_protection   = false
db_skip_final_snapshot   = true
redis_node_type          = "cache.t3.micro"
redis_replicas           = 0
