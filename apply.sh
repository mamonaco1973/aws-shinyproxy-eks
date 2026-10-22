#!/bin/bash
# ================================================================================
# FILE: apply.sh
# ================================================================================
#
# Purpose:
#   Orchestrate a four-phase deployment of the ShinyProxy app platform lab.
#
# Deployment Flow:
#     1. Deploy AD Domain Controller and VPC (Terraform).
#     2. Deploy EFS and domain-joined admin hosts (Terraform).
#     3. Create ECR repositories, then build and push the app session images
#        (VS Code, RStudio) and the ShinyProxy image (Terraform + Docker).
#     4. Deploy the ECS cluster, ShinyProxy service and ALB (Terraform).
#
# Design Principles:
#   - Strict sequencing to ensure AD is available before dependencies.
#   - Fail-fast behavior using set -euo pipefail.
#   - Images are tagged with a hash of their build context, so a changed
#     image always produces a changed task definition and a redeploy, and
#     an unchanged one never does.
#
# Requirements:
#   - AWS CLI configured with sufficient IAM permissions.
#   - Terraform and Docker installed and in PATH.
#   - check_env.sh and validate.sh present in working directory.
#
# Exit Codes:
#   0 = Success
#   1 = Validation failure or provisioning error
#
# ================================================================================


# ================================================================================
# SECTION: Configuration
# ================================================================================

# Target AWS region.
export AWS_DEFAULT_REGION="us-east-1"

# Fail on errors, unset variables, and pipe failures.
set -euo pipefail


# ================================================================================
# SECTION: Environment Validation
# ================================================================================

echo "NOTE: Running environment validation..."
./check_env.sh


# ================================================================================
# PHASE 1: Active Directory Deployment
# ================================================================================

echo "NOTE: Building Active Directory instance..."

cd 01-directory
terraform init
terraform apply -auto-approve
cd ..


# ================================================================================
# PHASE 2: EFS and Admin Servers
# ================================================================================

echo "NOTE: Building EFS and EC2 server instances..."

cd 02-servers
terraform init
terraform apply -auto-approve
cd ..


# ================================================================================
# PHASE 3: Container Images
# ================================================================================

echo "NOTE: Creating ECR repositories..."

cd 03-images
terraform init
terraform apply -auto-approve

vscode_repo=$(terraform output -raw vscode_session_repository_url)
rstudio_repo=$(terraform output -raw rstudio_session_repository_url)
shinyproxy_repo=$(terraform output -raw shinyproxy_repository_url)

# One tag for every image, derived from all build contexts (including the
# shared identity code in common/).
image_tag=$(find common vscode rstudio shinyproxy -type f -print0 | sort -z \
  | xargs -0 sha256sum | sha256sum | cut -c1-12)

echo "NOTE: Image tag: ${image_tag}"

registry="${vscode_repo%%/*}"
aws ecr get-login-password | docker login --username AWS --password-stdin "$registry"

# Session images build from 03-images/ so they can copy common/.
echo "NOTE: Building VS Code session image..."
docker build --platform linux/amd64 -f vscode/Dockerfile \
  -t "${vscode_repo}:${image_tag}" .
docker push "${vscode_repo}:${image_tag}"

echo "NOTE: Building RStudio session image..."
docker build --platform linux/amd64 -f rstudio/Dockerfile \
  -t "${rstudio_repo}:${image_tag}" .
docker push "${rstudio_repo}:${image_tag}"

echo "NOTE: Building ShinyProxy image..."
docker build --platform linux/amd64 -t "${shinyproxy_repo}:${image_tag}" shinyproxy
docker push "${shinyproxy_repo}:${image_tag}"

cd ..


# ================================================================================
# PHASE 4: ECS Cluster and ShinyProxy
# ================================================================================

echo "NOTE: Building ECS cluster and ShinyProxy service..."

cd 04-ecs
terraform init
terraform apply -auto-approve -var "image_tag=${image_tag}"

echo "NOTE: Waiting for the ShinyProxy service to stabilize..."
aws ecs wait services-stable --cluster shinyproxy --services shinyproxy
cd ..


# ================================================================================
# SECTION: Post-Deployment Validation
# ================================================================================

./validate.sh
