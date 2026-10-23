#!/bin/bash
# ==============================================================================
# session-identity.sh - Become the AD User (shared by every app image)
# ------------------------------------------------------------------------------
# Purpose:
#   - Sourced, as root, by each app's session-entrypoint.sh. Resolves the
#     signed-in user's POSIX identity from Active Directory, loads every AD
#     user and group into the container's passwd/group files (so file owners
#     on EFS show as names), grants linux-admins sudo, and makes sure the
#     user's home directory exists on EFS.
#   - The app entrypoint then starts its own server as that user.
#
# Inputs (environment):
#   SHINYPROXY_USERNAME  Set by ShinyProxy to the authenticated username.
#   LDAP_URL             e.g. ldap://10.0.0.10:389
#   LDAP_BASE_DN         e.g. DC=shinyproxyeks,DC=mikecloud,DC=com
#   LDAP_BIND_DN         Read-only service account DN.
#   LDAP_BIND_PASSWORD   From the ldap-bind Kubernetes secret (secretKeyRef).
#
# Sets for the caller:
#   USERNAME USER_UID USER_GID HOME_DIR, and run_as_user, log, die.
#
# The bind password lives only in a root-only file while this runs, and is
# deleted before it returns; callers must still exec their server with a
# clean environment (env -i), as LDAP_* values are otherwise inherited.
# ==============================================================================

SESSION_LIB="$(dirname "${BASH_SOURCE[0]}")"

log() { echo "session-entrypoint: $*"; }
die() { echo "session-entrypoint: ERROR: $*" >&2; exit 1; }

# ------------------------------------------------------------------------------
# Validate inputs
# ------------------------------------------------------------------------------
USERNAME="${SHINYPROXY_USERNAME:-}"
[ -n "$USERNAME" ] || die "SHINYPROXY_USERNAME is not set"

# The name ends up in an LDAP filter, a passwd entry and a path. Refuse
# anything outside the conservative POSIX set rather than try to escape it.
USERNAME="${USERNAME,,}"
[[ "$USERNAME" =~ ^[a-z_][a-z0-9._-]{0,31}$ ]] \
  || die "username '$USERNAME' is not a valid POSIX name"

for var in LDAP_URL LDAP_BASE_DN LDAP_BIND_DN LDAP_BIND_PASSWORD; do
  [ -n "${!var:-}" ] || die "$var is not set"
done

# ------------------------------------------------------------------------------
# LDAP helpers
# ------------------------------------------------------------------------------
PWFILE="$(mktemp)"
chmod 0600 "$PWFILE"
printf '%s' "$LDAP_BIND_PASSWORD" > "$PWFILE"
unset LDAP_BIND_PASSWORD
trap 'rm -f "$PWFILE"' EXIT

ldap_query() {
  # -o ldif-wrap=no keeps long DNs on one line so the parsing below holds.
  ldapsearch -x -LLL -o ldif-wrap=no -o nettimeout=10 \
    -H "$LDAP_URL" -D "$LDAP_BIND_DN" -y "$PWFILE" \
    -b "$LDAP_BASE_DN" "$@"
}

# ------------------------------------------------------------------------------
# Resolve the user
# ------------------------------------------------------------------------------
user_ldif="$(ldap_query "(&(objectClass=user)(sAMAccountName=$USERNAME))" \
  uidNumber gidNumber)" || die "LDAP search for $USERNAME failed"

USER_DN="$(sed -n 's/^dn: //p' <<< "$user_ldif" | head -1)"
USER_UID="$(sed -n 's/^uidNumber: //p' <<< "$user_ldif" | head -1)"
USER_GID="$(sed -n 's/^gidNumber: //p' <<< "$user_ldif" | head -1)"

[ -n "$USER_DN" ]  || die "$USERNAME not found in AD"
[ -n "$USER_UID" ] || die "$USERNAME has no uidNumber"
[ -n "$USER_GID" ] || die "$USERNAME has no gidNumber"

# Refuse system ranges outright: a mis-set uidNumber of 0 would otherwise
# hand the session root on the shared file system.
[ "$USER_UID" -ge 1000 ] || die "$USERNAME has system uidNumber $USER_UID"
[ "$USER_GID" -ge 1000 ] || die "$USERNAME has system gidNumber $USER_GID"

log "resolved $USERNAME uid=$USER_UID gid=$USER_GID"

# ------------------------------------------------------------------------------
# Load every AD user and group into /etc/passwd and /etc/group
# ------------------------------------------------------------------------------
# Not just this user: with the whole directory present, every uidNumber and
# gidNumber on EFS resolves to a name (ls -l /home shows edavis, not 10002).
# A snapshot taken now - see directory-sync.py for the rules.
python3 -I "$SESSION_LIB/directory-sync.py" "$PWFILE" \
  || die "loading users and groups from AD failed"

# The sync must have produced exactly the identity resolved above.
[ "$(id -u "$USERNAME" 2>/dev/null)" = "$USER_UID" ] \
  || die "$USERNAME did not load as uid $USER_UID (name or uid clash?)"

HOME_DIR="/home/$USERNAME"

log "groups: $(id -nG "$USERNAME")"

# Same rule the EC2 nodes applied: linux-admins get sudo.
if getent group linux-admins >/dev/null; then
  echo "%linux-admins ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/10-linux-admins
  chmod 0440 /etc/sudoers.d/10-linux-admins
fi

# ------------------------------------------------------------------------------
# Home directory (EFS)
# ------------------------------------------------------------------------------
# Usually already created by the Samba gateway. Create it here for users
# that have never signed in anywhere, matching pam_mkhomedir's layout.
if [ ! -d "$HOME_DIR" ]; then
  log "creating $HOME_DIR"
  mkdir -p "$HOME_DIR"
  cp -a /etc/skel/. "$HOME_DIR/"
  [ -d /efs ] && ln -sfn /efs "$HOME_DIR/efs"
  chown -R "$USER_UID:$USER_GID" "$HOME_DIR"
  chmod 0700 "$HOME_DIR"
fi

run_as_user() {
  setpriv --reuid="$USER_UID" --regid="$USER_GID" --init-groups "$@"
}

# The password file has served its purpose; nothing after this needs it.
rm -f "$PWFILE"
trap - EXIT
