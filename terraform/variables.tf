variable "project" {
  description = "The name of the project used to prefix resources"
  type        = string
}

variable "owner" {
  description = "The identifier of the project owner (name, email, etc...)"
  type        = string
}

variable "region" {
  description = "AWS region to host resources"
  type        = string
  default     = "eu-west-3"
}

variable "vpc" {
  description = "The main config object describing the VPC"
  type = object({
    cidr = string
    subnets = list(object({
      name = string
      cidr = string
      az   = string
      type = string # "public" | "private"
    }))
  })
}

variable "eks_cluster" {
  description = "EKS cluster config. 'subnets' = control plane + LB placement pool, node groups pin their own."
  type = object({
    name    = string
    version = string
    subnets = list(string)
    node_groups = list(object({
      name    = string
      subnets = list(string)
      labels  = map(string)
    }))
  })
}

variable "ecr_registries" {
  description = "ECR repositories to create. Images are built and pushed by CI."
  type = list(object({
    name = string
  }))
  default = []
}
