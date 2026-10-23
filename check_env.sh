#!/bin/bash
# ==============================================================================
# check_env.sh - Environment Validation
# ------------------------------------------------------------------------------
# Purpose:
#   - Validates that required CLI tools are available in the current PATH.
#   - Verifies AWS CLI authentication and connectivity.
#
# Scope:
#   - Checks for aws, terraform, jq, docker and kubectl binaries.
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
#   - kubectl installed (destroy.sh uses it to clear session pods).
# ==============================================================================

set -euo pipefail

# ------------------------------------------------------------------------------
# Required Commands
# ------------------------------------------------------------------------------
echo "NOTE: Validating required commands in PATH."

commands=("aws" "terraform" "jq" "docker" "kubectl")

for cmd in "${commands[@]}"; do
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "ERROR: Required command not found: ${cmd}"
    exit 1
  fi

  echo "NOTE: Found required command: ${cmd}"
done

echo "NOTE: All required commands are available."

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
