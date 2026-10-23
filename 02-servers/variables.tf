# ================================================================================
# FILE: variables.tf
# ================================================================================
#
# Purpose:
#   Define naming and infrastructure input variables for Active Directory
#   deployment and supporting VPC resources.
#
# Naming Model:
#   - dns_zone : Fully Qualified Domain Name for AD DNS namespace.
#   - realm    : Kerberos realm (uppercase FQDN).
#   - netbios  : Short legacy domain name (<= 15 characters).
#
# Notes:
#   - dns_zone, realm, and netbios must remain logically consistent.
#   - realm should equal upper(dns_zone) for Kerberos compatibility.
#   - netbios should avoid special characters and exceed neither 15 chars.
#
# ================================================================================


# ================================================================================
# SECTION: Active Directory DNS Zone (FQDN)
# ================================================================================

# Fully Qualified Domain Name used for AD DNS namespace.
# Example: shinyproxyeks.mikecloud.com
variable "dns_zone" {
  description = "Active Directory DNS zone (FQDN)"
  type        = string
  default     = "shinyproxyeks.mikecloud.com"
}


# ================================================================================
# SECTION: Kerberos Realm
# ================================================================================

# Kerberos realm value. Conventionally matches dns_zone in uppercase.
# Example: SHINYPROXYEKS.MIKECLOUD.COM
variable "realm" {
  description = "Kerberos realm (uppercase DNS zone)"
  type        = string
  default     = "SHINYPROXYEKS.MIKECLOUD.COM"
}


# ================================================================================
# SECTION: NetBIOS Short Domain Name
# ================================================================================

# Legacy NetBIOS-compatible short domain name.
# Typically uppercase, alphanumeric, <= 15 characters.
# Example: SHINYPROXYEKS
variable "netbios" {
  description = "NetBIOS short domain name"
  type        = string
  default     = "SHINYPROXYEKS"
}


# ================================================================================
# SECTION: VPC Naming
# ================================================================================

# Name assigned to the VPC resource created for this environment.
variable "vpc_name" {
  description = "Name for the VPC resource"
  type        = string
  default     = "shinyproxy-eks-vpc"
}
