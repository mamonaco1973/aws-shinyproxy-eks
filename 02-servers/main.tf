# ================================================================================
# FILE: main.tf
# ================================================================================
#
# Purpose:
#   Configure AWS provider and resolve shared AD environment dependencies used
#   by this root module. Lookups include:
#     - Secrets Manager secret for AD administrator credentials
#     - VPC and subnets for instance placement and AD connectivity
#     - Most recent Windows Server 2022 AMI published by Amazon
#
# Design:
#   - Provider is pinned to us-east-1 for consistent lab deployments.
#   - Infrastructure is discovered via tag-based and VPC-scoped data sources.
#   - Windows AMI lookup is constrained to official Amazon-published images.
#
# ================================================================================


# ================================================================================
# SECTION: AWS Provider
# ================================================================================

# Default deployment region for this configuration.
provider "aws" {
  region = "us-east-1"
}


# ================================================================================
# SECTION: Secrets Manager - AD Administrator Credentials
# ================================================================================

# Retrieve Secrets Manager secret metadata for AD admin credential access.
# Note: Reading secret value requires aws_secretsmanager_secret_version.
data "aws_secretsmanager_secret" "admin_secret" {
  name = "admin_ad_credentials_shinyproxy"
}


# ================================================================================
# SECTION: VPC Lookup - Active Directory Environment
# ================================================================================

# Locate AD VPC by Name tag to scope all subnet lookups and deployments.
data "aws_vpc" "ad_vpc" {
  filter {
    name   = "tag:Name"
    values = [var.vpc_name]
  }
}


# ================================================================================
# SECTION: Subnet Lookups - Placement and Routing
# ================================================================================

# Resolve subnets by Name tag and restrict to the AD VPC for safety.
# These subnets are used for VM placement, public resources, and AD access.

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

data "aws_subnet" "ad_subnet" {
  filter {
    name   = "tag:Name"
    values = ["ad-subnet"]
  }

  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.ad_vpc.id]
  }
}


# ================================================================================
# SECTION: AMI Lookup - Windows Server 2022
# ================================================================================

# Select most recent Windows Server 2022 base AMI published by Amazon.
# AMI selection is pattern-based and should remain stable across patch releases.
data "aws_ami" "windows_ami" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["Windows_Server-2022-English-Full-Base-*"]
  }
}
