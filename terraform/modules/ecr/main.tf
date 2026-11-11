resource "aws_ecr_repository" "this" {
  name                 = var.repository_name
  image_tag_mutability = "MUTABLE"
  force_delete         = true # allows destroy even with images in the repo

  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }
}

# builds & pushes when image_tag is non-empty; re-runs on tag/path change
resource "terraform_data" "push" {
  count = var.image_tag != "" ? 1 : 0

  depends_on = [aws_ecr_repository.this]

  triggers_replace = {
    repo_url = aws_ecr_repository.this.repository_url
    tag      = var.image_tag
    path     = var.image_path
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -euo pipefail

      aws ecr get-login-password --region ${var.region} \
        | docker login --username AWS --password-stdin ${aws_ecr_repository.this.repository_url}

      docker build -t ${var.repository_name}:${var.image_tag} ${var.image_path}
      docker tag  ${var.repository_name}:${var.image_tag} ${aws_ecr_repository.this.repository_url}:${var.image_tag}
      docker push ${aws_ecr_repository.this.repository_url}:${var.image_tag}
    EOT
  }
}
