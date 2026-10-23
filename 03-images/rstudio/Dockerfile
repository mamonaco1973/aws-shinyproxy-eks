# ==============================================================================
# Dockerfile - RStudio Session Image
# ------------------------------------------------------------------------------
# Purpose:
#   - One container of this image is one user's RStudio session. ShinyProxy
#     launches it as a pod per signed-in user and proxies to :8787.
#
# Identity Model:
#   - Same as the VS Code image: the entrypoint starts as root, becomes the
#     AD user via common/session-identity.sh, then starts rserver in
#     single-user mode (auth-none) with that user as the session owner.
#     ShinyProxy has already authenticated the user; rserver's own sign-in
#     page is never shown.
#
# Base image:
#   - rocker/rstudio: R plus RStudio Server (open source, AGPL), with CRAN
#     pointed at Posit Package Manager's prebuilt Linux binaries, so most
#     install.packages() calls need no compiler.
#   - rocker's own /init is NOT used: its env setup copies every container
#     environment variable into R's Renviron.site, which would hand the LDAP
#     bind password to every R session.
# ==============================================================================

FROM rocker/rstudio:4.6.1

RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      ldap-utils \
 && rm -rf /var/lib/apt/lists/*

# The image's default "rstudio" account is replaced by the real AD user.
RUN userdel -r rstudio 2>/dev/null || true

# Build context is 03-images/ (see apply.sh), so the shared identity code in
# common/ is reachable alongside this image's own files.
COPY rstudio/session-entrypoint.sh /usr/local/bin/session-entrypoint.sh
COPY rstudio/rstudio-prefs.json /etc/rstudio/rstudio-prefs.json
COPY common/session-identity.sh common/directory-sync.py /usr/local/lib/session/
RUN chmod 0755 /usr/local/bin/session-entrypoint.sh \
 && chmod 0644 /usr/local/lib/session/* /etc/rstudio/rstudio-prefs.json

EXPOSE 8787

ENTRYPOINT ["/usr/local/bin/session-entrypoint.sh"]
CMD []
