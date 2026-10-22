#!/bin/bash
# ==============================================================================
# session-entrypoint.sh - Become the AD User, Then Start code-server
# ------------------------------------------------------------------------------
# Purpose:
#   - Runs as root inside the session task. session-identity.sh (shared
#     with the other app images) becomes the AD user; this script prepares
#     the editor state and execs code-server under that identity.
#
# Design Notes:
#   - The bind password never reaches code-server: session-identity.sh
#     deletes it, and the final exec runs with a fresh environment.
#   - code-server state is split. Settings, keybindings, snippets and
#     extensions live on EFS so they follow the user between sessions. The
#     SQLite stores (globalStorage, workspaceStorage) are symlinked onto the
#     task's local disk - SQLite over NFS is the classic corruption case -
#     so editor layout and recent-files history reset with each session.
# ==============================================================================

set -euo pipefail

# Validate inputs, resolve the AD user, load users/groups, prepare home.
source /usr/local/lib/session/session-identity.sh

# ------------------------------------------------------------------------------
# Editor state
# ------------------------------------------------------------------------------
DATA_DIR="$HOME_DIR/.local/share/code-server"
LOCAL_STATE="/var/lib/vscode/$USERNAME"

# Created as the user so ownership on EFS is right without a chown pass.
run_as_user mkdir -p "$DATA_DIR/User" "$DATA_DIR/extensions"

mkdir -p "$LOCAL_STATE/globalStorage" "$LOCAL_STATE/workspaceStorage"
chown -R "$USER_UID:$USER_GID" "$LOCAL_STATE"
chmod 0700 "$LOCAL_STATE"

# Point the SQLite stores at local disk. A real directory left behind (e.g.
# by a session started outside this image) is moved aside, not deleted.
for store in globalStorage workspaceStorage; do
  link="$DATA_DIR/User/$store"
  if [ -e "$link" ] && [ ! -L "$link" ]; then
    run_as_user mv "$link" "$link.efs-$(date +%s)"
  fi
  run_as_user ln -sfn "$LOCAL_STATE/$store" "$link"
done

if [ ! -f "$DATA_DIR/User/settings.json" ]; then
  run_as_user cp /etc/vscode-default-settings.json "$DATA_DIR/User/settings.json"
fi

# ------------------------------------------------------------------------------
# Start code-server as the user
# ------------------------------------------------------------------------------
# --auth none is safe only because the task's security group admits port
# 8080 from ShinyProxy alone. ShinyProxy is the only path in.
log "starting code-server for $USERNAME"
cd "$HOME_DIR"

exec setpriv --reuid="$USER_UID" --regid="$USER_GID" --init-groups \
  env -i \
    HOME="$HOME_DIR" \
    USER="$USERNAME" \
    LOGNAME="$USERNAME" \
    SHELL=/bin/bash \
    PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    LANG="${LANG:-en_US.UTF-8}" \
    EXTENSIONS_GALLERY="$EXTENSIONS_GALLERY" \
  /usr/bin/code-server \
    --bind-addr 0.0.0.0:8080 \
    --auth none \
    --disable-telemetry \
    --disable-update-check \
    --user-data-dir "$DATA_DIR" \
    --extensions-dir "$DATA_DIR/extensions" \
    "$HOME_DIR"
