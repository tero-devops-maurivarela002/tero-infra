environment = "prod"
aws_region  = "us-east-1"

# Red: un NAT por zona para que la caída de una zona no deje sin salida a la otra
vpc_cidr           = "10.30.0.0/16"
az_count           = 2
single_nat_gateway = false
