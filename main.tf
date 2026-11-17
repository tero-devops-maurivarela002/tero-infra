# Por ahora solo se lee la identidad de la cuenta para comprobar que el
# backend y las credenciales funcionan. Los módulos (red, ECS, ALB, base de
# datos) se agregan en DEVOPS-42 y DEVOPS-43.
data "aws_caller_identity" "current" {}

data "aws_region" "current" {}
