variable "project" {
  description = "The name of the project used to prefix resources"
  type        = string
}

variable "region" {
  description = "AWS region (used to build AZ names)"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block of the VPC"
  type        = string
}

variable "subnets" {
  description = "Subnet definitions, keyed by their 'name' field"
  type = list(object({
    name = string
    cidr = string
    az   = string
    type = string
  }))
}

variable "cluster_name" {
  description = "EKS cluster name, used for the shared cluster tag on subnets"
  type        = string
}
