variable "region" {
  description = "AWS region for the repository and docker login"
  type        = string
}

variable "repository_name" {
  description = "Name of the ECR repository"
  type        = string
}

variable "scan_on_push" {
  description = "Enable ECR basic scanning on push"
  type        = bool
  default     = true
}
