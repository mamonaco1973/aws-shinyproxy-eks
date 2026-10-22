# ================================================================================
# FILE: iam.tf
# ================================================================================
#
# Purpose:
#   Define IAM role, policy, and instance profile for EC2 instances requiring
#   read access to AWS Secrets Manager and integration with AWS Systems Manager.
#
# Design:
#   - Role trusted by EC2 service via sts:AssumeRole.
#   - Custom policy restricts Secrets Manager access to specific secret ARN.
#   - AWS managed SSM policy enables Systems Manager agent functionality.
#   - Stable unique suffix prevents name collisions across deployments.
#
# ================================================================================


# ================================================================================
# SECTION: Stable Unique Identifier
# ================================================================================

# Generate short random suffix (stable per Terraform state).
resource "random_id" "iam_suffix" {
  byte_length = 3
}

# Construct normalized IAM identifier.
locals {
  iam_id = "${lower(var.netbios)}-${random_id.iam_suffix.hex}"
}


# ================================================================================
# SECTION: IAM Role - EC2 Secrets Access
# ================================================================================

# IAM role trusted by EC2 service.
resource "aws_iam_role" "ec2_secrets_role" {
  name = "tf-secrets-role-${local.iam_id}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}


# ================================================================================
# SECTION: IAM Policy - Secrets Manager Read Access
# ================================================================================

# Custom policy granting read-only access to AD admin secret.
resource "aws_iam_policy" "secrets_policy" {
  name        = "SecretsManagerReadAccess-${local.iam_id}"
  description = "Read access to specific Secrets Manager secret"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = [
          data.aws_secretsmanager_secret.admin_secret.arn
        ]
      }
    ]
  })
}


# ================================================================================
# SECTION: IAM Role Policy Attachments
# ================================================================================

# Attach AWS managed SSM policy for Systems Manager integration.
resource "aws_iam_role_policy_attachment" "attach_ssm_policy" {
  role       = aws_iam_role.ec2_secrets_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Attach custom Secrets Manager read policy to EC2 role.
resource "aws_iam_role_policy_attachment" "attach_secrets_policy" {
  role       = aws_iam_role.ec2_secrets_role.name
  policy_arn = aws_iam_policy.secrets_policy.arn
}


# ================================================================================
# SECTION: IAM Instance Profile
# ================================================================================

# Instance profile binds IAM role for EC2 association.
resource "aws_iam_instance_profile" "ec2_secrets_profile" {
  name = "tf-secrets-profile-${local.iam_id}"
  role = aws_iam_role.ec2_secrets_role.name
}
