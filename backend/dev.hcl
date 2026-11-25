# Backend del ambiente dev. El bucket NO va acá: se pasa en el init con
#   -backend-config="bucket=tero-tfstate-<ID de la cuenta>"
# para no dejar el ID de la cuenta en el repo y poder cambiar de cuenta de Academy.
key          = "dev/terraform.tfstate"
region       = "us-east-1"
encrypt      = true
use_lockfile = true
