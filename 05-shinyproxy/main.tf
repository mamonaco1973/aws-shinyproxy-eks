# ================================================================================
# FILE: main.tf
# ================================================================================
#
# Purpose:
#   Configure the AWS and Kubernetes providers and look up everything earlier
#   phases built: VPC (01), the domain controller (01), the LDAP service
#   account secret (01), EFS (02), the ECR repositories (03), and the EKS
#   cluster and ALB target group (04).
#
# Design:
#   A separate phase from 04 so the Kubernetes provider is configured from a
#   cluster that already exists. The token comes from the caller's AWS
#   identity, which phase 04 made cluster admin; no kubeconfig is needed.
#
# ================================================================================

provider "aws" {
  region = "us-east-1"
}

data "aws_eks_cluster" "shinyproxy" {
  name = var.cluster_name
}

data "aws_eks_cluster_auth" "shinyproxy" {
  name = var.cluster_name
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.shinyproxy.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.shinyproxy.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.shinyproxy.token
}


# ================================================================================
# SECTION: Networking
# ================================================================================

data "aws_vpc" "ad_vpc" {
  filter {
    name   = "tag:Name"
    values = [var.vpc_name]
  }
}

data "aws_lb_target_group" "shinyproxy" {
  name = "shinyproxy-eks-tg"
}


# ================================================================================
# SECTION: Directory
# ================================================================================

# The domain controller, addressed by IP so LDAP does not depend on the
# pod resolving the AD DNS zone.
data "aws_instance" "domain_controller" {
  filter {
    name   = "tag:Name"
    values = ["mini-ad-dc-${lower(var.netbios)}"]
  }
  filter {
    name   = "instance-state-name"
    values = ["running"]
  }
}

data "aws_secretsmanager_secret" "shinyproxy_ldap" {
  name = "shinyproxy_eks_ldap_credentials"
}

# Read so it can be copied into a Kubernetes Secret (shinyproxy.tf). The
# value is therefore also in this phase's state, as it already is in 01's.
data "aws_secretsmanager_secret_version" "shinyproxy_ldap" {
  secret_id = data.aws_secretsmanager_secret.shinyproxy_ldap.id
}


# ================================================================================
# SECTION: Storage and Images
# ================================================================================

data "aws_efs_file_system" "efs" {
  tags = {
    Name = "shinyproxy-eks-efs"
  }
}

data "aws_ecr_repository" "vscode_session" {
  name = "vscode-session-eks"
}

data "aws_ecr_repository" "rstudio_session" {
  name = "rstudio-session-eks"
}

data "aws_ecr_repository" "shinyproxy" {
  name = "shinyproxy-eks"
}


# ================================================================================
# SECTION: Derived Values
# ================================================================================

locals {
  ldap_url     = "ldap://${data.aws_instance.domain_controller.private_ip}:389"
  ldap_bind_dn = "CN=ShinyProxy Service,${var.user_base_dn}"

  vscode_image     = "${data.aws_ecr_repository.vscode_session.repository_url}:${var.image_tag}"
  rstudio_image    = "${data.aws_ecr_repository.rstudio_session.repository_url}:${var.image_tag}"
  shinyproxy_image = "${data.aws_ecr_repository.shinyproxy.repository_url}:${var.image_tag}"

  # ShinyProxy and every session pod run here.
  namespace = "shinyproxy"

  # Selects the ShinyProxy pod in the Service and the network policies.
  shinyproxy_labels = { "app.kubernetes.io/name" = "shinyproxy" }
}
