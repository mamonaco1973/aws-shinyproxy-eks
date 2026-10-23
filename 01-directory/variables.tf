# ================================================================================
# FILE: variables.tf
# ================================================================================
#
# Purpose:
#   Define Active Directory naming inputs and supporting infrastructure
#   variables required for mini-AD deployment.
#
# Naming Model:
#   - dns_zone     : Fully Qualified Domain Name for AD namespace.
#   - realm        : Kerberos realm (uppercase FQDN).
#   - netbios      : Short legacy domain name (<= 15 characters).
#   - user_base_dn : LDAP Distinguished Name for user object placement.
#
# Consistency Requirements:
#   - realm should equal upper(dns_zone).
#   - user_base_dn must align with dns_zone components.
#   - netbios should be uppercase and <= 15 characters.
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
# SECTION: LDAP User Base Distinguished Name
# ================================================================================

# Distinguished Name under which user accounts will be created.
# Must correspond to DNS domain components.
# Example: CN=Users,DC=shinyproxyeks,DC=mikecloud,DC=com
variable "user_base_dn" {
  description = "LDAP user base distinguished name"
  type        = string
  default     = "CN=Users,DC=shinyproxyeks,DC=mikecloud,DC=com"
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
