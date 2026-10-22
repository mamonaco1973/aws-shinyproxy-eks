#!/bin/bash
# ================================================================================
# FILE: destroy.sh
# ================================================================================
#
# Purpose:
#   Tear down the VS Code on ShinyProxy lab in reverse dependency order.
#
# Teardown Flow:
#     1. Stop any session tasks still running, and remove the per-session
#        task definitions ShinyProxy registered outside Terraform.
#     2. Destroy the ECS cluster, ShinyProxy service and ALB.
#     3. Destroy the ECR repositories (images included).
#     4. Destroy EFS and admin servers.
#     5. Delete Secrets Manager entries, then the domain controller and VPC.
#
# ================================================================================

set -euo pipefail

export AWS_DEFAULT_REGION="us-east-1"

CLUSTER="shinyproxy"


# ================================================================================
# PHASE 1: Session Tasks and Task Definitions
# ================================================================================

# ShinyProxy stops its sessions on a clean shutdown, but a crashed or
# force-stopped ShinyProxy leaves them running, and ECS refuses to delete a
# cluster that still has tasks.
if aws ecs describe-clusters --clusters "$CLUSTER" \
     --query "clusters[?status=='ACTIVE'].clusterName" --output text | grep -q .; then
  echo "NOTE: Scaling ShinyProxy to zero..."
  aws ecs update-service --cluster "$CLUSTER" --service shinyproxy \
    --desired-count 0 >/dev/null 2>&1 || true

  for task in $(aws ecs list-tasks --cluster "$CLUSTER" \
                  --query "taskArns[]" --output text); do
    echo "NOTE: Stopping task: ${task##*/}"
    aws ecs stop-task --cluster "$CLUSTER" --task "$task" >/dev/null
  done
fi

echo "NOTE: Removing ShinyProxy session task definitions..."
for td in $(aws ecs list-task-definitions --family-prefix sp-task-definition- \
              --status ACTIVE --query "taskDefinitionArns[]" --output text); do
  aws ecs deregister-task-definition --task-definition "$td" >/dev/null
done

inactive=$(aws ecs list-task-definitions --family-prefix sp-task-definition- \
             --status INACTIVE --query "taskDefinitionArns[]" --output text)
if [ -n "$inactive" ]; then
  # delete-task-definitions accepts at most 10 ARNs per call.
  echo "$inactive" | tr '\t' '\n' | xargs -n 10 \
    aws ecs delete-task-definitions --task-definitions >/dev/null
fi


# ================================================================================
# PHASE 2: ECS Cluster and ShinyProxy
# ================================================================================

echo "NOTE: Destroying ECS cluster and ShinyProxy service..."

cd 04-ecs
terraform init
terraform destroy -auto-approve
cd ..


# ================================================================================
# PHASE 3: Container Images
# ================================================================================

echo "NOTE: Destroying ECR repositories..."

cd 03-images
terraform init
terraform destroy -auto-approve
cd ..


# ================================================================================
# PHASE 4: EFS and Admin Servers
# ================================================================================

echo "NOTE: Destroying EC2 server instances..."

cd 02-servers
terraform init
terraform destroy -auto-approve
cd ..


# ================================================================================
# PHASE 5: Secrets and Active Directory
# ================================================================================

echo "NOTE: Deleting AD-related Secrets Manager entries..."

for secret in \
  akumar_ad_credentials_shinyproxy \
  jsmith_ad_credentials_shinyproxy \
  edavis_ad_credentials_shinyproxy \
  rpatel_ad_credentials_shinyproxy \
  admin_ad_credentials_shinyproxy \
  shinyproxy_ldap_credentials; do
  aws secretsmanager delete-secret \
    --secret-id "$secret" \
    --force-delete-without-recovery || true
done

echo "NOTE: Destroying Active Directory instance..."

cd 01-directory
terraform init
terraform destroy -auto-approve
cd ..

echo "NOTE: Infrastructure teardown complete."
