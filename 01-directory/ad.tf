# ================================================================================
# FILE: ad.tf
# ================================================================================
#
# Purpose:
#   Invoke the reusable mini-ad module to provision an Ubuntu-based Active
#   Directory Domain Controller. Pass required networking, DNS, and identity
#   parameters. Supply user account definitions via rendered JSON payload.
#
# Design:
#   - Delegates AD infrastructure to external versioned module.
#   - Injects randomized administrator and user credentials.
#   - Supplies rendered JSON for automated user bootstrap.
#   - Enforces dependency ordering for outbound internet access.
#
# Operational Notes:
#   - NAT and route associations must exist before instance bootstrap.
#   - users_json is rendered at apply time and passed to cloud-init.
#   - Passwords originate from accounts.tf (random admin, word-number users).
#
# ================================================================================


# ================================================================================
# SECTION: Mini Active Directory Module Invocation
# ================================================================================

# Provision Ubuntu-based AD Domain Controller using reusable module.
module "mini_ad" {
  source            = "github.com/mamonaco1973/module-aws-mini-ad?ref=sentinel"
  netbios           = var.netbios
  vpc_id            = aws_vpc.ad-vpc.id
  realm             = var.realm
  users_json        = local.users_json
  user_base_dn      = var.user_base_dn
  ad_admin_password = random_password.admin_password.result
  dns_zone          = var.dns_zone
  subnet_id         = aws_subnet.ad-subnet.id

  # Ensure outbound connectivity exists before bootstrap execution.
  depends_on = [
    aws_nat_gateway.ad_nat,
    aws_route_table_association.rt_assoc_ad_private
  ]
}


# ================================================================================
# SECTION: Local Variable - users_json Rendering
# ================================================================================

# Render users.json.template into single JSON payload for bootstrap.
# Inject randomized passwords and directory context values at apply time.
locals {
  users_json = templatefile("./scripts/users.json.template", {
    USER_BASE_DN        = var.user_base_dn
    DNS_ZONE            = var.dns_zone
    REALM               = var.realm
    NETBIOS             = var.netbios
    jsmith_password     = local.passwords["jsmith"]
    edavis_password     = local.passwords["edavis"]
    rpatel_password     = local.passwords["rpatel"]
    akumar_password     = local.passwords["akumar"]
    shinyproxy_password = random_password.shinyproxy_password.result
  })
}
