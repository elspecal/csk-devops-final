resource "aws_security_group" "cluster" {
  name        = "${var.name}-cluster-sg"
  description = "EKS cluster control plane security group"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "node" {
  name        = "${var.name}-node-sg"
  description = "EKS worker node security group"
  vpc_id      = var.vpc_id
}

# Kubernetes API reachable from the nodes
resource "aws_security_group_rule" "node_to_cluster_api" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.cluster.id
  source_security_group_id = aws_security_group.node.id
}

# kubelet (logs, exec, port-forward)
resource "aws_security_group_rule" "cluster_to_node_kubelet" {
  type                     = "ingress"
  from_port                = 10250
  to_port                  = 10250
  protocol                 = "tcp"
  security_group_id        = aws_security_group.node.id
  source_security_group_id = aws_security_group.cluster.id
}

resource "aws_security_group_rule" "node_to_node" {
  type              = "ingress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  security_group_id = aws_security_group.node.id
  self              = true
}

resource "aws_security_group_rule" "node_egress_all" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.node.id
}

# NLB traffic reaches targets from the NLB's internal ENIs, so we must allow
# the VPC CIDR (SG-to-SG references don't work for NLB-sourced traffic).
resource "aws_security_group_rule" "node_ingress_from_vpc" {
  type              = "ingress"
  from_port         = 30000
  to_port           = 32767
  protocol          = "tcp"
  cidr_blocks       = [var.vpc_cidr]
  security_group_id = aws_security_group.node.id
}
