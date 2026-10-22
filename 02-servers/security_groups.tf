# ================================================================================
# FILE: security_groups.tf
# ================================================================================
#
# Purpose:
#   Define security groups for Windows and Linux instances within the AD lab.
#   Exposes RDP (3389), SSH (22), SMB (445), and ICMP for testing scenarios.
#
# WARNING:
#   - Inbound rules allow 0.0.0.0/0 and are NOT production safe.
#   - Use only for controlled lab or demonstration environments.
#   - Restrict to trusted CIDR ranges or VPN in production deployments.
#
# Design:
#   - Separate security groups for Windows (RDP) and Linux (SSH/SMB).
#   - ICMP enabled for diagnostic reachability testing.
#   - All outbound traffic permitted by default.
#
# ================================================================================


# ================================================================================
# SECTION: Security Group - Windows RDP Access
# ================================================================================

# Allows inbound RDP and ICMP for Windows hosts.
resource "aws_security_group" "ad_rdp_sg" {
  name        = "ad-rdp-security-group"
  description = "Allow RDP access for lab environments"
  vpc_id      = data.aws_vpc.ad_vpc.id

  # --------------------------------------------------------------------------
  # Ingress: RDP (TCP 3389)
  # --------------------------------------------------------------------------
  ingress {
    description = "Allow RDP from anywhere (lab only)"
    from_port   = 3389
    to_port     = 3389
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # --------------------------------------------------------------------------
  # Ingress: ICMP (Ping)
  # --------------------------------------------------------------------------
  ingress {
    description = "Allow ICMP from anywhere (lab only)"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # --------------------------------------------------------------------------
  # Egress: Allow All Outbound
  # --------------------------------------------------------------------------
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


# ================================================================================
# SECTION: Security Group - Linux SSH and SMB Access
# ================================================================================

# Allows inbound SSH, SMB, and ICMP for Linux hosts.
resource "aws_security_group" "ad_ssh_sg" {
  name        = "ad-ssh-security-group"
  description = "Allow SSH and SMB access for lab environments"
  vpc_id      = data.aws_vpc.ad_vpc.id

  # --------------------------------------------------------------------------
  # Ingress: SSH (TCP 22)
  # --------------------------------------------------------------------------
  ingress {
    description = "Allow SSH from anywhere (lab only)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # --------------------------------------------------------------------------
  # Ingress: SMB (TCP 445)
  # --------------------------------------------------------------------------
  ingress {
    description = "Allow SMB from anywhere (lab only)"
    from_port   = 445
    to_port     = 445
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # --------------------------------------------------------------------------
  # Ingress: standalone code-server (TCP 9090)
  # --------------------------------------------------------------------------
  # For running a single-user code-server by hand on this host — the stock
  # deployment the cluster exists to improve on. Nothing in the cluster uses
  # this port.
  ingress {
    description = "Allow standalone code-server from anywhere (lab only)"
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # --------------------------------------------------------------------------
  # Ingress: ICMP (Ping)
  # --------------------------------------------------------------------------
  ingress {
    description = "Allow ICMP from anywhere (lab only)"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # --------------------------------------------------------------------------
  # Egress: Allow All Outbound
  # --------------------------------------------------------------------------
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
