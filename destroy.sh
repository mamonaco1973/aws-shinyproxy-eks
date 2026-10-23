#!/bin/bash
# ================================================================================
# FILE: destroy.sh
# ================================================================================
#
# Purpose:
#   Tear down the ShinyProxy on EKS lab in reverse dependency order.
#
# Teardown Flow:
#     1. Stop ShinyProxy and delete any session pods still running, then
#        destroy the rest of the ShinyProxy phase and its namespace.
#     2. Destroy the EKS cluster (Auto Mode terminates its nodes) and ALB.
#     3. Destroy the ECR repositories (images included).
#     4. Destroy EFS and admin servers.
#     5. Delete Secrets Manager entries, then the domain controller and VPC.
#
# Requirements:
#   - AWS CLI, Terraform and kubectl in PATH.
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
  # ShinyProxy deletes its session pods on a clean shutdown, but any it has
  # lost track of keep running. While a pod mounts the EFS claim, Kubernetes
  # will not delete the claim, and Terraform waits on it forever - so stop
  # ShinyProxy first, then remove whatever session pods are left.
  echo "NOTE: Stopping ShinyProxy and removing session pods..."

  aws eks update-kubeconfig --name "$CLUSTER" >/dev/null
  kubectl -n shinyproxy delete deployment shinyproxy \
    --ignore-not-found --wait=true --timeout=180s
  kubectl -n shinyproxy delete pod -l openanalytics.eu/sp-proxied-app=true \
    --ignore-not-found --wait=true --timeout=300s

  echo "NOTE: Destroying the ShinyProxy phase..."

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
