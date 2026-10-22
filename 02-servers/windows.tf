# ================================================================================
# FILE: windows.tf
# ================================================================================
#
# Purpose:
#   Provision Windows Server EC2 instance used as Active Directory
#   administrative workstation.
#
# Role:
#   - NOT a Domain Controller.
#   - Used for RDP access, RSAT tools, ADUC, and PowerShell management.
#   - Connects to and manages AD services hosted elsewhere.
#
# Design:
#   - AMI dynamically resolved via data source.
#   - Public IP assigned for lab accessibility.
#   - IAM instance profile enables Secrets Manager and SSM access.
#   - Bootstrapped via PowerShell user data script.
#
# WARNING:
#   - Public IP + permissive RDP security group is not production safe.
#   - Restrict RDP to trusted CIDR ranges or VPN in real deployments.
#
# ================================================================================


# ================================================================================
# SECTION: EC2 Instance - Windows AD Administration Server
# ================================================================================

resource "aws_instance" "windows_ad_instance" {

  # --------------------------------------------------------------------------
  # Amazon Machine Image
  # --------------------------------------------------------------------------
  # Latest supported Windows Server AMI resolved via data source.
  ami = data.aws_ami.windows_ami.id

  # --------------------------------------------------------------------------
  # Instance Type
  # --------------------------------------------------------------------------
  # Balanced compute profile suitable for AD administration tools.
  instance_type = "t3.medium"

  # --------------------------------------------------------------------------
  # Networking
  # --------------------------------------------------------------------------
  # - Launched into designated subnet.
  # - Security group permits RDP access.
  subnet_id = data.aws_subnet.pub_subnet_1.id

  vpc_security_group_ids = [
    aws_security_group.ad_rdp_sg.id
  ]

  # Assign public IP at launch for lab RDP access.
  associate_public_ip_address = true

  # --------------------------------------------------------------------------
  # IAM Instance Profile
  # --------------------------------------------------------------------------
  # Grants controlled access to AWS APIs (Secrets Manager, SSM).
  iam_instance_profile = aws_iam_instance_profile.ec2_secrets_profile.name

  # --------------------------------------------------------------------------
  # User Data Bootstrapping
  # --------------------------------------------------------------------------
  # PowerShell script performs:
  #   - Domain join using stored admin credentials
  #   - Integration with Samba/EFS gateway
  #   - RDP group configuration
  user_data = templatefile("./scripts/userdata.ps1", {
    admin_secret = "admin_ad_credentials_shinyproxy"
    domain_fqdn  = var.dns_zone
    samba_server = aws_instance.efs_gateway_instance.private_dns
    rdp_group    = "shinyproxy-users"
    netbios      = var.netbios
  })

  # --------------------------------------------------------------------------
  # Tags
  # --------------------------------------------------------------------------
  # Resource identification and cost allocation metadata.
  tags = {
    Name = "windows-ad-admin"
  }

  # --------------------------------------------------------------------------
  # Dependencies
  # --------------------------------------------------------------------------
  # Ensure gateway instance exists prior to admin server provisioning.
  depends_on = [
    aws_instance.efs_gateway_instance
  ]
}
