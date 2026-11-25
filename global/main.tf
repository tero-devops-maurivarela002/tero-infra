# Recursos compartidos por los 3 ambientes (DEVOPS-26).
#
# ECR va acá y no en cada ambiente porque la MISMA imagen (mismo tag = SHA del
# commit) se promueve de dev a test y a prod: no se reconstruye. Por eso hay
# un solo repositorio por servicio, con su propio state (global/terraform.tfstate).

resource "aws_ecr_repository" "this" {
  for_each = var.services

  name = "${var.repository_prefix}/${each.key}"

  # Un tag no se puede pisar: <servicio>:<sha> siempre es la misma imagen.
  # Así "la imagen que se probó en dev" es exactamente la que llega a prod.
  image_tag_mutability = "IMMUTABLE"

  # Escaneo de vulnerabilidades de AWS en cada push (además de Trivy en el
  # pipeline). El resultado lo usa la Lambda de seguridad (DEVOPS-46).
  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    # KMS con la clave administrada por AWS (aws/ecr): no hay que crear ni pagar una clave propia.
    encryption_type = "KMS"
  }

  # Permite borrar el repositorio aunque tenga imágenes (lab de Academy).
  force_delete = true
}

resource "aws_ecr_lifecycle_policy" "this" {
  for_each = aws_ecr_repository.this

  repository = each.value.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Guardar solo las ultimas ${var.images_to_keep} imagenes"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = var.images_to_keep
      }
      action = { type = "expire" }
    }]
  })
}
