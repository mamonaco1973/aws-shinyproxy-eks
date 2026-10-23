#!/bin/bash
# ================================================================================
# FILE: destroy.sh
# ================================================================================
#
# Purpose:
#   Tear down the ShinyProxy on EKS lab in reverse dependency order.
#
# Teardown Flow:
#     1. Destroy ShinyProxy and its namespace. ShinyProxy deletes its
#        session pods on shutdown; deleting the namespace removes any that
#        a crashed ShinyProxy left behind.
#     2. Destroy the EKS cluster (Auto Mode terminates its nodes) and ALB.
#     3. Destroy the ECR repositories (images included).
#     4. Destroy EFS and admin servers.
#     5. Delete Secrets Manager entries, then the domain controller and VPC.
#
# ================================================================================

set -euo pipefail

export AWS_DEFAULT_REGION="us-east-1"

CLUSTER="shinyproxy-eks"


# ================================================================================
# PHASE 1: ShinyProxy and Session Pods
# ================================================================================

# Phase 05 reads the cluster at plan time, so skip it once the cluster is
# gone (a re-run after a partial teardown).
if aws eks describe-cluster --name "$CLUSTER" >/dev/null 2>&1; then
  echo "NOTE: Destroying ShinyProxy and its session pods..."

  cd 05-shinyproxy
  terraform init
  terraform destroy -auto-approve
  cd ..
else
  echo "NOTE: EKS cluster ${CLUSTER} not found; skipping ShinyProxy teardown."
fi


# ================================================================================
# PHASE 2: EKS Cluster and ALB
# ================================================================================

echo "NOTE: Destroying EKS cluster and load balancer..."

cd 04-eks
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
  akumar_ad_credentials_shinyproxy_eks \
  jsmith_ad_credentials_shinyproxy_eks \
  edavis_ad_credentials_shinyproxy_eks \
  rpatel_ad_credentials_shinyproxy_eks \
  admin_ad_credentials_shinyproxy_eks \
  shinyproxy_eks_ldap_credentials; do
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
