#!/bin/bash
# ==============================================================================
# check_env.sh - Environment Validation
# ------------------------------------------------------------------------------
# Purpose:
#   - Validates that required CLI tools are available in the current PATH.
#   - Verifies AWS CLI authentication and connectivity.
#
# Scope:
#   - Checks for aws, terraform, jq and docker binaries.
#   - Reports whether kubectl is present (optional: troubleshooting only).
#   - Confirms the caller identity via AWS STS.
#
# Fast-Fail Behavior:
#   - Script exits immediately on command failure, unset variables,
#     or failed pipelines.
#
# Requirements:
#   - AWS CLI installed and configured.
#   - Terraform installed.
#   - jq installed.
#   - Docker installed, with the daemon reachable by this user.
# ==============================================================================

set -euo pipefail

# ------------------------------------------------------------------------------
# Required Commands
# ------------------------------------------------------------------------------
echo "NOTE: Validating required commands in PATH."

commands=("aws" "terraform" "jq" "docker")

for cmd in "${commands[@]}"; do
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "ERROR: Required command not found: ${cmd}"
    exit 1
  fi

  echo "NOTE: Found required command: ${cmd}"
done

echo "NOTE: All required commands are available."

# Not needed to deploy - Terraform talks to the cluster itself - but it is
# how you look at pods and logs afterwards.
if command -v kubectl >/dev/null 2>&1; then
  echo "NOTE: Found optional command: kubectl"
else
  echo "NOTE: Optional command not found: kubectl (needed only for troubleshooting)"
fi

# ------------------------------------------------------------------------------
# AWS Connectivity Check
# ------------------------------------------------------------------------------
echo "NOTE: Verifying Docker daemon access..."
docker info >/dev/null 2>&1 || {
  echo "ERROR: Docker daemon not reachable. Start Docker or add this user to the docker group."
  exit 1
}
echo "NOTE: Docker daemon reachable."

echo "NOTE: Verifying AWS CLI connectivity..."

aws sts get-caller-identity --query "Account" --output text >/dev/null

echo "NOTE: AWS CLI authentication successful."
