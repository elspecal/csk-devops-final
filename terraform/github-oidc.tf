# --- GitHub Actions OIDC: CI assumes this role, no access keys anywhere ---

# exists once per account: use data, not resource
data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

# trust: only pushes to main of this repo may assume the role
data "aws_iam_policy_document" "gha_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # GitHub's sub includes the owner/repo IDs on newer repos:
    #   repo:<owner>@<owner-id>/<repo>@<repo-id>:ref:refs/heads/main
    # accept both that and the classic format, scoped to this repo + main
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:elspecal/csk-devops-final:ref:refs/heads/main",
        "repo:elspecal@*/csk-devops-final@*:ref:refs/heads/main",
      ]
    }
  }
}

resource "aws_iam_role" "gha" {
  name               = "${var.project}-gha"
  assume_role_policy = data.aws_iam_policy_document.gha_trust.json
}

# course-level: the pipeline provisions VPC/EKS/ECR/IAM and pushes images
resource "aws_iam_role_policy_attachment" "gha_admin" {
  role       = aws_iam_role.gha.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# lets the runner reach the cluster API: kubectl, and the kubernetes/helm
# providers (aws eks get-token authenticates with the assumed role)
resource "aws_eks_access_entry" "gha" {
  cluster_name  = module.eks.cluster_name
  principal_arn = aws_iam_role.gha.arn
}

resource "aws_eks_access_policy_association" "gha" {
  cluster_name  = module.eks.cluster_name
  principal_arn = aws_eks_access_entry.gha.principal_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }
}
