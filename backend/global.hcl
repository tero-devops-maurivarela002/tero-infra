# Backend de los recursos compartidos (ECR). El bucket se pasa en el init:
#   -backend-config="bucket=tero-tfstate-<ID de la cuenta>"
key          = "global/terraform.tfstate"
region       = "us-east-1"
encrypt      = true
use_lockfile = true
