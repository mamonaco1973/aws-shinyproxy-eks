# ================================================================================
# FILE: variables.tf
# ================================================================================
#
# Purpose:
#   Define input variables for Active Directory naming, LDAP lookups, the
#   cluster to deploy into and the image tag to run.
#
# ================================================================================


# ================================================================================
# SECTION: NetBIOS Short Domain Name
# ================================================================================

# Used only to find the domain controller instance by its Name tag.
variable "netbios" {
  description = "NetBIOS short domain name"
  type        = string
  default     = "SHINYPROXYEKS"
}


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

variable "cluster_name" {
  description = "Name of the EKS cluster built by phase 04"
  type        = string
  default     = "shinyproxy-eks"
}


# ================================================================================
# SECTION: LDAP Naming
# ================================================================================

# Domain root DN; ShinyProxy and session containers search beneath it.
variable "base_dn" {
  description = "LDAP base distinguished name of the domain"
  type        = string
  default     = "DC=shinyproxyeks,DC=mikecloud,DC=com"
}

# Container under which the mini-AD module creates users and groups.
variable "user_base_dn" {
  description = "LDAP user base distinguished name"
  type        = string
  default     = "CN=Users,DC=shinyproxyeks,DC=mikecloud,DC=com"
}


# ================================================================================
# SECTION: Image Tag
# ================================================================================

# Tag apply.sh pushes every image under. Changing it restarts ShinyProxy
# and points new sessions at the new session images.
variable "image_tag" {
  description = "Tag of the ShinyProxy and session images in ECR"
  type        = string
  default     = "latest"
}
