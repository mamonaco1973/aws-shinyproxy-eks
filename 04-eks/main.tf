# ================================================================================
# FILE: main.tf
# ================================================================================
#
# Purpose:
#   Configure the AWS provider and look up the VPC and subnets phase 01
#   built. This phase creates only AWS resources - the EKS cluster, its
#   IAM roles, the EFS CSI add-on and the ALB. Everything inside the
#   cluster is phase 05.
#
# ================================================================================

provider "aws" {
  region = "us-east-1"
}

data "aws_region" "current" {}


# ================================================================================
# SECTION: Networking
# ================================================================================

data "aws_vpc" "ad_vpc" {
  filter {
    name   = "tag:Name"
    values = [var.vpc_name]
  }
}

# Private subnets (NAT egress) - the cluster, its nodes and every pod.
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
