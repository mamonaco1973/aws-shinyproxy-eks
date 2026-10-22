# ================================================================================
# FILE: iam.tf
# ================================================================================
#
# Purpose:
#   IAM roles for the two kinds of task in this cluster.
#
# Role Map:
#   shinyproxy_execution : ECS agent pulls the ShinyProxy image, writes its
#                          logs and injects the LDAP bind password.
#   shinyproxy_task      : ShinyProxy itself - registers a task definition per
#                          session, runs and stops session tasks.
#   session_execution    : ECS agent pulls the session image, writes session
#                          logs and injects the LDAP bind password.
#
# Design Notes:
#   - Session tasks get NO task role. code-server has no reason to call AWS,
#     and a role would hand every user its credentials.
#   - iam:PassRole is limited to the session execution role, so ShinyProxy
#     cannot launch a task under any other identity.
#
# ================================================================================

resource "random_id" "iam_suffix" {
  byte_length = 3
}

locals {
  iam_id = "shinyproxy-${random_id.iam_suffix.hex}"
}

data "aws_iam_policy_document" "ecs_tasks_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# Shared by both execution roles: read the one LDAP secret, and create the
# per-app log groups the awslogs driver asks for (awslogs-create-group).
data "aws_iam_policy_document" "execution_extras" {
  statement {
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [data.aws_secretsmanager_secret.shinyproxy_ldap.arn]
  }

  statement {
    actions   = ["logs:CreateLogGroup"]
    resources = ["arn:aws:logs:*:${data.aws_caller_identity.current.account_id}:log-group:/ecs/shinyproxy/*"]
  }
}


# ================================================================================
# SECTION: ShinyProxy Execution Role
# ================================================================================

resource "aws_iam_role" "shinyproxy_execution" {
  name               = "shinyproxy-exec-${local.iam_id}"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

resource "aws_iam_role_policy_attachment" "shinyproxy_execution_managed" {
  role       = aws_iam_role.shinyproxy_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "shinyproxy_execution_extras" {
  name   = "execution-extras"
  role   = aws_iam_role.shinyproxy_execution.id
  policy = data.aws_iam_policy_document.execution_extras.json
}


# ================================================================================
# SECTION: ShinyProxy Task Role
# ================================================================================

data "aws_iam_policy_document" "shinyproxy_task" {
  # Task definitions are registered per session, so their ARNs are not
  # known in advance. ECS does not support resource-level scoping for
  # Register/List actions.
  statement {
    actions = [
      "ecs:RegisterTaskDefinition",
      "ecs:DeregisterTaskDefinition",
      "ecs:DeleteTaskDefinitions",
      "ecs:ListTaskDefinitions",
      "ecs:DescribeTaskDefinition",
      "ecs:ListTagsForResource",
      "ecs:TagResource",
    ]
    resources = ["*"]
  }

  statement {
    actions = [
      "ecs:RunTask",
      "ecs:StopTask",
      "ecs:DescribeTasks",
    ]
    resources = ["*"]

    condition {
      test     = "ArnEquals"
      variable = "ecs:cluster"
      values   = [aws_ecs_cluster.shinyproxy.arn]
    }
  }

  statement {
    actions   = ["iam:PassRole"]
    resources = [aws_iam_role.session_execution.arn]
  }
}

resource "aws_iam_role" "shinyproxy_task" {
  name               = "shinyproxy-task-${local.iam_id}"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

resource "aws_iam_role_policy" "shinyproxy_task" {
  name   = "launch-sessions"
  role   = aws_iam_role.shinyproxy_task.id
  policy = data.aws_iam_policy_document.shinyproxy_task.json
}


# ================================================================================
# SECTION: Session Execution Role
# ================================================================================

resource "aws_iam_role" "session_execution" {
  name               = "app-session-exec-${local.iam_id}"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

resource "aws_iam_role_policy_attachment" "session_execution_managed" {
  role       = aws_iam_role.session_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "session_execution_extras" {
  name   = "execution-extras"
  role   = aws_iam_role.session_execution.id
  policy = data.aws_iam_policy_document.execution_extras.json
}
