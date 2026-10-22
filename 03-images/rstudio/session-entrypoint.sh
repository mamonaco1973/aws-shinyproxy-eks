#!/bin/bash
# ==============================================================================
# session-entrypoint.sh - Become the AD User, Then Start RStudio Server
# ------------------------------------------------------------------------------
# Purpose:
#   - Runs as root inside the session task. session-identity.sh (shared
#     with the other app images) becomes the AD user; this script configures
#     rserver for single-user use behind ShinyProxy and execs it.
#
# Design Notes:
#   - rserver itself stays root (it must, to start sessions) and launches
#     the R session as the AD user. In auth-none mode it takes that user
#     from the USER environment variable.
#   - The final exec runs with a fresh environment: no LDAP_* variable
#     reaches rserver or any R session.
#   - www-root-path is ShinyProxy's per-session path (/app_proxy/<id>/).
#     Without it RStudio builds absolute redirects to "/" and leaves the
#     proxy.
#   - www-frame-origin=same lets ShinyProxy show RStudio in its iframe;
#     RStudio's default refuses to be framed at all.
#   - User state (~/.local/share/rstudio, ~/.config/rstudio, R libraries in
#     ~/R) lives in the EFS home and follows the user between sessions.
#     rserver's own database stays on local disk under /var/lib/rstudio-server.
# ==============================================================================

set -euo pipefail

# Validate inputs, resolve the AD user, load users/groups, prepare home.
source /usr/local/lib/session/session-identity.sh

# ------------------------------------------------------------------------------
# rserver configuration
# ------------------------------------------------------------------------------
ROOT_PATH="${SHINYPROXY_PUBLIC_PATH:-/}"
[[ "$ROOT_PATH" =~ ^/[A-Za-z0-9/._-]*$ ]] || die "unexpected public path '$ROOT_PATH'"

# auth-none is safe only because the task's security group admits port 8787
# from ShinyProxy alone. ShinyProxy is the only path in.
cat > /etc/rstudio/rserver.conf <<EOF
rsession-which-r=/usr/local/bin/R
auth-none=1
auth-minimum-user-id=1000
www-address=0.0.0.0
www-port=8787
www-root-path=$ROOT_PATH
www-frame-origin=same
EOF

log "starting rstudio-server for $USERNAME (root path $ROOT_PATH)"
cd /

exec env -i \
  USER="$USERNAME" \
  HOME="$HOME_DIR" \
  PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
  LANG="${LANG:-en_US.UTF-8}" \
  TZ="${TZ:-Etc/UTC}" \
  R_HOME="${R_HOME:-/usr/local/lib/R}" \
  /usr/lib/rstudio-server/bin/rserver --server-daemonize=0
