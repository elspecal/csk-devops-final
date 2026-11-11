output "cluster_name" {
  description = "Name of the EKS cluster"
  value       = module.eks.cluster_name
}

output "ecr_repository_urls" {
  description = "ECR repository URLs to tag & push images to"
  value       = { for name, repo in module.ecr : name => repo.repository_url }
}
