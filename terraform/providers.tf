provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Owner   = var.owner
      Project = var.project
    }
  }
}
