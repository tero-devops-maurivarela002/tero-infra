environment = "test"
aws_region  = "us-east-1"

# Red
vpc_cidr           = "10.20.0.0/16"
az_count           = 2
single_nat_gateway = true

# Panel admin: las IPs NO se versionan (repo público). El pipeline las toma del
# secret ADMIN_ALLOWED_CIDRS; a mano: -var='admin_allowed_cidrs=["<tu IP>/32"]'
admin_allowed_cidrs     = []
alb_deletion_protection = false

# ECS: image_tag no va acá. El pipeline usa el SHA que ya corre en el ambiente
# (scripts/ci/preparar-variables.sh); a mano: -var="image_tag=<sha>"
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

# Rotación de secretos (docs/runbooks/rotacion-de-secretos.md): subir en 1 y
# mergear el PR. El apply cambia la contraseña y reinicia los servicios.
db_password_version  = 1
admin_secret_version = 1
