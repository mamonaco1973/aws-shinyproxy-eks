# ================================================================================
# FILE: eks.tf
# ================================================================================
#
# Purpose:
#   EKS cluster in Auto Mode that runs ShinyProxy and every user's session
#   pod, plus the EFS CSI driver that mounts the shared file system into
#   those pods.
#
# Compute Model:
#   Auto Mode runs AWS-managed Karpenter. There are no node groups: when a
#   pod cannot be scheduled, Auto Mode launches an EC2 instance sized for it,
#   and removes the instance once nothing is left on it. Sessions pack onto
#   shared nodes, so a second session on a warm node skips both the instance
#   launch and the image pull.
#
#   The built-in general-purpose pool (on-demand c/m/r, amd64) carries
#   ShinyProxy and the sessions; the system pool carries cluster add-ons.
#
# Session Pods:
#   Not defined here or in Terraform at all. ShinyProxy creates one pod per
#   session through the Kubernetes API and deletes it when the session
#   ends. Their shape comes from the specs in 03-images/shinyproxy/
#   application.yml; the namespace, RBAC and network policies that contain
#   them are phase 05.
#
# Design Notes:
#   - Auto Mode also runs the load balancer controller, which phase 05 uses
#     to keep the ALB's target group pointed at the ShinyProxy pod.
#   - The endpoint is public so Terraform can reach it from the workstation,
#     and private so ShinyProxy reaches it from inside the VPC.
#   - Access entries (API mode) only. The identity that runs apply.sh is the
#     cluster admin; nothing else is granted.
#
# ================================================================================

resource "aws_eks_cluster" "shinyproxy" {
  name     = var.cluster_name
  version  = var.kubernetes_version
  role_arn = aws_iam_role.cluster.arn

  # Auto Mode supplies networking, DNS and kube-proxy itself.
  bootstrap_self_managed_addons = false

  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = true
  }

  # Auto Mode requires compute, load balancing and block storage together.
  compute_config {
    enabled       = true
    node_pools    = ["general-purpose", "system"]
    node_role_arn = aws_iam_role.node.arn
  }

  kubernetes_network_config {
    elastic_load_balancing {
      enabled = true
    }
  }

  storage_config {
    block_storage {
      enabled = true
    }
  }

  vpc_config {
    subnet_ids              = [data.aws_subnet.vm_subnet_1.id, data.aws_subnet.vm_subnet_2.id]
    endpoint_private_access = true
    endpoint_public_access  = true
  }

  # The role's policies must be attached before EKS assumes it, and must
  # outlive the cluster on destroy so Auto Mode can clean up its instances.
  depends_on = [
    aws_iam_role_policy_attachment.cluster,
    aws_iam_role_policy_attachment.node,
  ]
}


# ================================================================================
# SECTION: EFS CSI Driver
# ================================================================================

# Mounts EFS into session pods through a static PersistentVolume (phase 05).
# Auto Mode bundles the EBS driver but not this one.
resource "aws_eks_addon" "efs_csi" {
  cluster_name = aws_eks_cluster.shinyproxy.name
  addon_name   = "aws-efs-csi-driver"

  # Auto Mode runs the Pod Identity agent on every node.
  pod_identity_association {
    role_arn        = aws_iam_role.efs_csi.arn
    service_account = "efs-csi-controller-sa"
  }
}


# ================================================================================
# SECTION: Outputs
# ================================================================================

output "cluster_name" {
  value = aws_eks_cluster.shinyproxy.name
}

output "cluster_endpoint" {
  value = aws_eks_cluster.shinyproxy.endpoint
}
