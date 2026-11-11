# AWS Load Balancer Controller via Helm, IAM via EKS Pod Identity.
# Once present, it handles type: LoadBalancer Services (NLB by default) and Ingresses.
resource "aws_iam_policy" "lbc" {
  name        = "${var.name}_lbc_policy"
  description = "Official policy for the AWS Load Balancer Controller"
  policy      = file("${path.module}/loadbalancer_controller.json")
}

data "aws_iam_policy_document" "lbc" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }

    actions = [
      "sts:AssumeRole",
      "sts:TagSession",
    ]
  }
}

resource "aws_iam_role" "lbc" {
  name               = "${var.name}-aws-lbc"
  assume_role_policy = data.aws_iam_policy_document.lbc.json
}

resource "aws_iam_role_policy_attachment" "lbc" {
  role       = aws_iam_role.lbc.name
  policy_arn = aws_iam_policy.lbc.arn
}

resource "aws_eks_pod_identity_association" "lbc" {
  cluster_name    = aws_eks_cluster.this.name
  namespace       = "kube-system"
  service_account = "aws-load-balancer-controller"
  role_arn        = aws_iam_role.lbc.arn
}

resource "helm_release" "lbc" {
  name       = "aws-load-balancer-controller"
  namespace  = "kube-system"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  # no version pin -> latest chart

  set = [
    { name = "clusterName", value = aws_eks_cluster.this.name },
    { name = "region", value = var.region },
    { name = "serviceAccount.name", value = "aws-load-balancer-controller" },
    { name = "serviceAccount.create", value = "true" },
    { name = "vpcId", value = var.vpc_id },
  ]

  depends_on = [
    aws_eks_pod_identity_association.lbc,
    aws_eks_addon.pod_identity_agent,
    aws_eks_node_group.this,
  ]
}
