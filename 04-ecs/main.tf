# ================================================================================
# FILE: main.tf
# ================================================================================
#
# Purpose:
#   Configure the AWS provider and look up everything earlier phases built:
#   VPC and subnets (01), the domain controller (01), the LDAP service
#   account secret (01), EFS (02) and the ECR repositories (03).
#
# ================================================================================

provider "aws" {
  region = "us-east-1"
}

data "aws_region" "current" {}

data "aws_caller_identity" "current" {}


# ================================================================================
# SECTION: Networking
# ================================================================================

data "aws_vpc" "ad_vpc" {
  filter {
    name   = "tag:Name"
    values = [var.vpc_name]
  }
}

# Private subnets (NAT egress) - ShinyProxy and session tasks run here.
data "aws_subnet" "vm_subnet_1" {
  filter {
    name   = "tag:Name"
    values = ["vm-subnet-1"]
  }
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.ad_vpc.id]
  }
}

data "aws_subnet" "vm_subnet_2" {
  filter {
    name   = "tag:Name"
    values = ["vm-subnet-2"]
  }
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.ad_vpc.id]
  }
}

# Public subnets - the ALB only.
data "aws_subnet" "pub_subnet_1" {
  filter {
    name   = "tag:Name"
    values = ["pub-subnet-1"]
  }
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.ad_vpc.id]
  }
}

data "aws_subnet" "pub_subnet_2" {
  filter {
    name   = "tag:Name"
    values = ["pub-subnet-2"]
  }
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.ad_vpc.id]
  }
}


# ================================================================================
# SECTION: Directory
# ================================================================================

# The domain controller, addressed by IP so LDAP does not depend on the
# task resolving the AD DNS zone.
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
  name = "shinyproxy_ldap_credentials"
}


# ================================================================================
# SECTION: Storage and Images
# ================================================================================

data "aws_efs_file_system" "efs" {
  tags = {
    Name = "shinyproxy-efs"
  }
}

data "aws_ecr_repository" "vscode_session" {
  name = "vscode-session"
}

data "aws_ecr_repository" "rstudio_session" {
  name = "rstudio-session"
}

data "aws_ecr_repository" "shinyproxy" {
  name = "shinyproxy"
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

  cluster_name = "shinyproxy"
}
