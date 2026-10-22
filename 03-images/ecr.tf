# ================================================================================
# FILE: ecr.tf
# ================================================================================
#
# Purpose:
#   Create the ECR repositories this project pushes to:
#     - vscode-session  : one container per user's VS Code session
#     - rstudio-session : one container per user's RStudio session
#     - shinyproxy      : ShinyProxy with this project's configuration
#
# Design:
#   - Images are built and pushed by apply.sh with the local Docker daemon;
#     Terraform only owns the repositories.
#   - force_delete lets destroy.sh remove a repository that still holds
#     images, which a lab teardown always will.
#
# ================================================================================

resource "aws_ecr_repository" "vscode_session" {
  name                 = "vscode-session"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = false
  }
}

resource "aws_ecr_repository" "rstudio_session" {
  name                 = "rstudio-session"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = false
  }
}

resource "aws_ecr_repository" "shinyproxy" {
  name                 = "shinyproxy"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = false
  }
}

output "vscode_session_repository_url" {
  value = aws_ecr_repository.vscode_session.repository_url
}

output "rstudio_session_repository_url" {
  value = aws_ecr_repository.rstudio_session.repository_url
}

output "shinyproxy_repository_url" {
  value = aws_ecr_repository.shinyproxy.repository_url
}
