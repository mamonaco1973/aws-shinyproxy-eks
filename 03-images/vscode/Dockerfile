# ==============================================================================
# Dockerfile - VS Code Session Image
# ------------------------------------------------------------------------------
# Purpose:
#   - One container of this image is one user's VS Code session. ShinyProxy
#     launches it as a Fargate task per signed-in user and proxies to :8080.
#
# Identity Model:
#   - The container starts as root ONLY long enough for session-entrypoint.sh
#     to resolve the ShinyProxy user's uidNumber/gidNumber from AD and load
#     every AD user and group into /etc/passwd and /etc/group
#     (common/session-identity.sh, shared with the other app images). It
#     then drops to the user's identity with setpriv
#     before code-server starts, so files on EFS-backed /home carry the same
#     POSIX ownership the Samba gateway and Windows host see, and every
#     owner shows as a name.
# ==============================================================================

FROM codercom/code-server:4.141.0

USER root

# ------------------------------------------------------------------------------
# Packages
# ------------------------------------------------------------------------------
# ldap-utils resolves POSIX attributes at start-up. The rest is a modest
# developer toolset; extend it here rather than in a running session, since
# anything installed into a session's root filesystem dies with the task.
#
# No C/C++ toolchain (build-essential): it adds ~300 MB to every session
# launch's image pull. Add it back here if sessions need to compile native
# code (C/C++, Python packages without prebuilt wheels).
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      ldap-utils python3 python3-pip python3-venv jq unzip less vim nano \
 && rm -rf /var/lib/apt/lists/*

# ------------------------------------------------------------------------------
# Remove the image's own user
# ------------------------------------------------------------------------------
# The upstream image runs as "coder" (uid 1000) with passwordless sudo. Every
# session here runs as a real AD identity instead, so the stock account and
# its blanket sudo rule are removed outright.
RUN userdel coder \
 && rm -f /etc/sudoers.d/nopasswd \
 && rm -rf /home/coder

# The upstream WORKDIR is /home/coder. The runtime recreates a missing
# working directory at container start - after EFS is mounted on /home - so
# leaving it would plant a root-owned /home/coder in the shared home
# directories. The entrypoint cds to the user's home itself.
WORKDIR /

# ------------------------------------------------------------------------------
# Extension gallery - Open VSX, deliberately
# ------------------------------------------------------------------------------
# A licensing boundary, not a preference: Microsoft's Marketplace terms permit
# access only from official Microsoft products. Set explicitly so a future
# override has to be a deliberate act.
ENV EXTENSIONS_GALLERY='{"serviceUrl":"https://open-vsx.org/vscode/gallery","itemUrl":"https://open-vsx.org/vscode/item"}'

# Build context is 03-images/ (see apply.sh), so the shared identity code in
# common/ is reachable alongside this image's own files.
COPY vscode/default-settings.json /etc/vscode-default-settings.json
COPY vscode/session-entrypoint.sh /usr/local/bin/session-entrypoint.sh
COPY common/session-identity.sh common/directory-sync.py /usr/local/lib/session/
RUN chmod 0755 /usr/local/bin/session-entrypoint.sh \
 && chmod 0644 /usr/local/lib/session/* \
 && chmod 0644 /etc/vscode-default-settings.json \
 && mkdir -p /var/lib/vscode \
 && chmod 0751 /var/lib/vscode

EXPOSE 8080

# dumb-init stays PID 1 as root, so /proc/1/environ (which still holds the
# LDAP bind password) is unreadable by the session user.
ENTRYPOINT ["/usr/bin/dumb-init", "/usr/local/bin/session-entrypoint.sh"]
