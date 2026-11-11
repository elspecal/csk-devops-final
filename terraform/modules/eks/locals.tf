locals {
  node_groups = { for ng in var.node_groups : ng.name => ng }
}

output "cluster_name" {
  value = aws_eks_cluster.this.name
}
