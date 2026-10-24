# ECR = AWS's private Docker image registry. The pipeline pushes images here and EKS pulls them.
locals {
  apps = ["noc-console", "device-simulator"]
}

resource "aws_ecr_repository" "app" {
  for_each = toset(local.apps)

  name = each.key
  # IMMUTABLE: a tag like sha-3e239c9 can never be overwritten, so a tag always means the same code.
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true # let `terraform destroy` remove repos that still hold images

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_lifecycle_policy" "app" {
  for_each   = aws_ecr_repository.app
  repository = each.value.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep only the 10 newest images"
      selection    = { tagStatus = "any", countType = "imageCountMoreThan", countNumber = 10 }
      action       = { type = "expire" }
    }]
  })
}
