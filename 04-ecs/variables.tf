# ================================================================================
# FILE: variables.tf
# ================================================================================
#
# Purpose:
#   Define input variables for Active Directory naming and supporting VPC
#   resource identification.
#
# Naming Model:
#   - dns_zone : Fully Qualified Domain Name for AD DNS namespace.
#   - realm    : Kerberos realm (uppercase dns_zone).
#   - netbios  : Short legacy domain name (<= 15 characters).
#
# Notes:
#   - realm should equal upper(dns_zone) for Kerberos compatibility.
#   - netbios should be uppercase and avoid special characters.
#
# ================================================================================


# ================================================================================
# SECTION: Active Directory DNS Zone (FQDN)
# ================================================================================

variable "dns_zone" {
  description = "Active Directory DNS zone (FQDN)"
  type        = string
  default     = "shinyproxy.mikecloud.com"
}


# ================================================================================
# SECTION: Kerberos Realm
# ================================================================================

variable "realm" {
  description = "Kerberos realm (uppercase DNS zone)"
  type        = string
  default     = "SHINYPROXY.MIKECLOUD.COM"
}


# ================================================================================
# SECTION: NetBIOS Short Domain Name
# ================================================================================

variable "netbios" {
  description = "NetBIOS short domain name"
  type        = string
  default     = "SHINYPROXY"
}


# ================================================================================
# SECTION: VPC Naming
# ================================================================================

variable "vpc_name" {
  description = "Name for the VPC resource"
  type        = string
  default     = "shinyproxy-vpc"
}


# ================================================================================
# SECTION: LDAP Naming
# ================================================================================

# Domain root DN; ShinyProxy and session containers search beneath it.
variable "base_dn" {
  description = "LDAP base distinguished name of the domain"
  type        = string
  default     = "DC=shinyproxy,DC=mikecloud,DC=com"
}

# Container under which the mini-AD module creates users and groups.
variable "user_base_dn" {
  description = "LDAP user base distinguished name"
  type        = string
  default     = "CN=Users,DC=shinyproxy,DC=mikecloud,DC=com"
}


# ================================================================================
# SECTION: Image Tag
# ================================================================================

# Tag apply.sh pushes both images under. Changing it rolls the ShinyProxy
# service and points new sessions at the new session image.
variable "image_tag" {
  description = "Tag of the ShinyProxy and session images in ECR"
  type        = string
  default     = "latest"
}
