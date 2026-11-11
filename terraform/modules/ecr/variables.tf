variable "region" {
  description = "AWS region for the repository and docker login"
  type        = string
}

variable "repository_name" {
  description = "Name of the ECR repository"
  type        = string
}

variable "image_path" {
  description = "Local directory containing the Dockerfile to build and push"
  type        = string
}

variable "image_tag" {
  description = "Tag to build/push. Empty string skips the build/push step."
  type        = string
}

variable "scan_on_push" {
  description = "Enable ECR basic scanning on push"
  type        = bool
  default     = true
}
