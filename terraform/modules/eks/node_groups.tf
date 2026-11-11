resource "aws_eks_node_group" "this" {
  for_each = local.node_groups

  cluster_name    = aws_eks_cluster.this.name
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = each.value.subnet_ids
  node_group_name = each.value.name

  ami_type       = "AL2023_x86_64_STANDARD"
  instance_types = [var.node_instance_type]
  capacity_type  = "ON_DEMAND"
  disk_size      = 20

  scaling_config {
    desired_size = 3
    min_size     = 3
    max_size     = 5
  }

  labels = each.value.labels

  depends_on = [
    aws_iam_role_policy_attachment.node_AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.node_AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.node_AmazonEC2ContainerRegistryReadOnly,
  ]
}
