# ================================================================================
# FILE: iam.tf
# ================================================================================
#
# Purpose:
#   IAM roles for the EKS control plane, its Auto Mode nodes and the EFS
#   CSI controller.
#
# Role Map:
#   cluster : EKS itself - and, in Auto Mode, the managed Karpenter, load
#             balancer controller and EBS driver running on its behalf.
#   node    : Every Auto Mode instance. Joins the cluster and pulls images
#             from ECR - nothing else.
#   efs_csi : The EFS CSI controller, through EKS Pod Identity.
#
# Design Notes:
#   - Neither ShinyProxy nor the sessions has an IAM role. ShinyProxy
#     launches sessions through the Kubernetes API (RBAC, phase 05), not an
#     AWS API, and the apps have no reason to call AWS; a role would hand
#     every user its credentials.
#   - Pods cannot borrow the node role: phase 05's network policy blocks
#     session pods from the instance metadata endpoint.
#
# ================================================================================

resource "random_id" "iam_suffix" {
  byte_length = 3
}

locals {
  iam_id = "shinyproxy-${random_id.iam_suffix.hex}"
}


# ================================================================================
# SECTION: Cluster Role
# ================================================================================

data "aws_iam_policy_document" "eks_assume" {
  statement {
    # Auto Mode tags the sessions it starts with the cluster name.
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cluster" {
  name               = "eks-cluster-${local.iam_id}"
  assume_role_policy = data.aws_iam_policy_document.eks_assume.json
}

resource "aws_iam_role_policy_attachment" "cluster" {
  for_each = toset([
    "AmazonEKSClusterPolicy",
    "AmazonEKSComputePolicy",
    "AmazonEKSBlockStoragePolicy",
    "AmazonEKSLoadBalancingPolicy",
    "AmazonEKSNetworkingPolicy",
  ])

  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/${each.key}"
}


# ================================================================================
# SECTION: Node Role
# ================================================================================

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

# EKS creates the access entry that lets this role join the cluster.
resource "aws_iam_role" "node" {
  name               = "eks-node-${local.iam_id}"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_role_policy_attachment" "node" {
  for_each = toset([
    "AmazonEKSWorkerNodeMinimalPolicy",
    "AmazonEC2ContainerRegistryPullOnly",
  ])

  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/${each.key}"
}


# ================================================================================
# SECTION: EFS CSI Controller Role
# ================================================================================

data "aws_iam_policy_document" "pod_identity_assume" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "efs_csi" {
  name               = "efs-csi-${local.iam_id}"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_assume.json
}

resource "aws_iam_role_policy_attachment" "efs_csi" {
  role       = aws_iam_role.efs_csi.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEFSCSIDriverPolicy"
}
