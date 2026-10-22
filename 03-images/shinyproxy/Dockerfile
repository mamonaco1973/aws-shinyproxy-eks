# ==============================================================================
# Dockerfile - ShinyProxy Image
# ------------------------------------------------------------------------------
# Purpose:
#   - Upstream ShinyProxy with this project's application.yml baked in.
#
# Note:
#   application.yml holds no deployment-specific values - those are ${...}
#   placeholders resolved from the ECS task environment - so this image only
#   needs rebuilding when the configuration itself changes.
# ==============================================================================

FROM openanalytics/shinyproxy:3.2.4

COPY --chown=shinyproxy:shinyproxy application.yml /opt/shinyproxy/application.yml

# VS Code-styled pages and assets; application.yml points template-path here.
COPY --chown=shinyproxy:shinyproxy templates /opt/shinyproxy/templates/theme
