# ================================================================================
# FILE: variables.tf
# ================================================================================
#
# Purpose:
#   Define input variables for the EKS cluster and supporting VPC resource
#   identification.
#
# ================================================================================


# ================================================================================
# SECTION: VPC Naming
# ================================================================================

variable "vpc_name" {
  description = "Name for the VPC resource"
  type        = string
  default     = "shinyproxy-eks-vpc"
}


# ================================================================================
# SECTION: Cluster
# ================================================================================

# Phase 05, apply.sh and destroy.sh all find the cluster by this name.
variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "shinyproxy-eks"
}

variable "kubernetes_version" {
  description = "Kubernetes version of the EKS cluster"
  type        = string
  default     = "1.37"
}
