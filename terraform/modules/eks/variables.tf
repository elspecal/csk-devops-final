variable "project" {
  description = "The name of the project used to prefix resources"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
}

variable "name" {
  description = "EKS cluster name"
  type        = string
}

variable "k8s_version" {
  description = "Kubernetes version of the EKS cluster"
  type        = string
}

variable "vpc_id" {
  description = "VPC the cluster lives in"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block of the VPC (used for NodePort ingress rules)"
  type        = string
}

variable "subnet_ids" {
  description = "Subnets given to the control plane / LB placement pool (>= 2 AZs required)"
  type        = list(string)
}

variable "node_groups" {
  description = "Managed node groups to create"
  type = list(object({
    name       = string
    labels     = map(string)
    subnet_ids = list(string)
  }))
}

variable "node_instance_type" {
  description = "EC2 instance type for the worker nodes"
  type        = string
  default     = "t3.small"
}

variable "configure_kubectl" {
  description = "If set, runs 'aws eks update-kubeconfig' after cluster creation"
  type = object({
    region = string
  })
  default = null
}
