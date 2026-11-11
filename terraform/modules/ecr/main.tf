resource "aws_ecr_repository" "this" {
  name                 = var.repository_name
  image_tag_mutability = "MUTABLE"
  force_delete         = true # allows destroy even with images in the repo

  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }
}
# image build & push now happens in .github/workflows/build-and-push.yml
