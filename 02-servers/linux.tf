# ================================================================================
# FILE: linux.tf
# ================================================================================
#
# Purpose:
#   Provision Ubuntu 24.04 EC2 instance acting as EFS client and AD-integrated
#   gateway host. Resolve AMI dynamically via SSM and enforce trusted owner.
#
# Design:
#   - Ubuntu AMI resolved from Canonical SSM public parameter.
#   - AMI owner restricted to Canonical AWS account (099720109477).
#   - Instance bootstrapped via parameterized user data template.
#   - IAM instance profile grants controlled AWS service access.
#
# ================================================================================


# ================================================================================
# SECTION: Canonical Ubuntu 24.04 AMI Lookup
# ================================================================================

# Retrieve latest Canonical Ubuntu 24.04 LTS AMI ID from SSM parameter store.
# Ensures deployments track current stable release without hardcoding AMI ID.
data "aws_ssm_parameter" "ubuntu_24_04" {
  name = "/aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id"
}


# ================================================================================
# SECTION: Resolve Trusted AMI Object
# ================================================================================

# Resolve full AMI object using ID from SSM.
# Restrict owner to Canonical to prevent spoofed or untrusted images.
data "aws_ami" "ubuntu_ami" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "image-id"
    values = [data.aws_ssm_parameter.ubuntu_24_04.value]
  }
}


# ================================================================================
# SECTION: EC2 Instance - EFS Gateway
# ================================================================================

resource "aws_instance" "efs_gateway_instance" {

  # --------------------------------------------------------------------------
  # Amazon Machine Image
  # --------------------------------------------------------------------------
  # Dynamically resolved Ubuntu 24.04 LTS AMI.
  ami = data.aws_ami.ubuntu_ami.id

  # --------------------------------------------------------------------------
  # Instance Type
  # --------------------------------------------------------------------------
  # Selected for balanced cost and performance for lab workloads.
  instance_type = "t3.medium"

  # --------------------------------------------------------------------------
  # Networking
  # --------------------------------------------------------------------------
  # - Placed in designated subnet.
  # - Security group restricts inbound access.
  subnet_id = data.aws_subnet.pub_subnet_1.id

  vpc_security_group_ids = [
    aws_security_group.ad_ssh_sg.id
  ]

  # Assign public IP at launch for direct SSH access if permitted by SG.
  associate_public_ip_address = true

  # --------------------------------------------------------------------------
  # IAM Instance Profile
  # --------------------------------------------------------------------------
  # Grants permissions for Secrets Manager retrieval and SSM management.
  iam_instance_profile = aws_iam_instance_profile.ec2_secrets_profile.name

  # --------------------------------------------------------------------------
  # User Data Bootstrapping
  # --------------------------------------------------------------------------
  # Executes initialization script with environment-specific parameters.
  # Script performs AD join, EFS mount, and Samba configuration.
  user_data = templatefile("./scripts/userdata.sh", {
    admin_secret   = "admin_ad_credentials_shinyproxy"
    domain_fqdn    = var.dns_zone
    efs_mnt_server = aws_efs_mount_target.efs_mnt_1.dns_name
    netbios        = var.netbios
    realm          = var.realm
    force_group    = "shinyproxy-users"
  })

  # --------------------------------------------------------------------------
  # Tags
  # --------------------------------------------------------------------------
  # Standard resource identification and cost allocation tagging.
  tags = {
    Name = "efs-samba-gateway"
  }

  # --------------------------------------------------------------------------
  # Dependencies
  # --------------------------------------------------------------------------
  # Ensure EFS and mount targets exist before instance provisioning.
  depends_on = [
    aws_efs_file_system.efs,
    aws_efs_mount_target.efs_mnt_1,
    aws_efs_mount_target.efs_mnt_2
  ]
}
