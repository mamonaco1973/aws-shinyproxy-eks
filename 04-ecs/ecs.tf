# ================================================================================
# FILE: ecs.tf
# ================================================================================
#
# Purpose:
#   ECS cluster that holds both the ShinyProxy service and every user's
#   session task, plus the ShinyProxy service itself.
#
# Session Tasks:
#   Not defined here. ShinyProxy registers a task definition per session
#   (family sp-task-definition-<proxy id>), runs it with RunTask, and
#   deregisters it when the session ends. Their shape comes from the specs
#   in 03-images/shinyproxy/application.yml.
#
# Design Notes:
#   - One ShinyProxy task. ShinyProxy holds session state in memory, and the
#     ECS backend has no app recovery: a restart stops every session, which
#     ShinyProxy does deliberately on shutdown rather than orphan tasks.
#     Running two would need Redis (proxy.store-mode: Redis).
#   - Deployment allows zero healthy tasks so the old ShinyProxy is gone
#     before the new one starts - two instances must never manage the same
#     sessions at once.
#
# ================================================================================

resource "aws_ecs_cluster" "shinyproxy" {
  name = local.cluster_name

  setting {
    name  = "containerInsights"
    value = "disabled"
  }
}


# ================================================================================
# SECTION: Log Groups
# ================================================================================

# Created here so destroy removes them. The session groups match the names
# ShinyProxy derives: <cloud-watch-group-prefix>sp-<spec id>.
resource "aws_cloudwatch_log_group" "shinyproxy" {
  name              = "/ecs/shinyproxy/server"
  retention_in_days = 7
}

resource "aws_cloudwatch_log_group" "sessions" {
  for_each          = toset(["vscode", "vscode-large", "rstudio"])
  name              = "/ecs/shinyproxy/sp-${each.key}"
  retention_in_days = 7
}


# ================================================================================
# SECTION: ShinyProxy Task Definition
# ================================================================================

resource "aws_ecs_task_definition" "shinyproxy" {
  family                   = "shinyproxy"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 1024
  memory                   = 2048
  execution_role_arn       = aws_iam_role.shinyproxy_execution.arn
  task_role_arn            = aws_iam_role.shinyproxy_task.arn

  runtime_platform {
    cpu_architecture        = "X86_64"
    operating_system_family = "LINUX"
  }

  container_definitions = jsonencode([{
    name      = "shinyproxy"
    image     = local.shinyproxy_image
    essential = true

    portMappings = [
      { containerPort = 8080, protocol = "tcp" },
      { containerPort = 9090, protocol = "tcp" },
    ]

    # Resolved into application.yml's ${...} placeholders by Spring.
    environment = [
      { name = "AWS_REGION", value = data.aws_region.current.region },
      { name = "ECS_CLUSTER", value = aws_ecs_cluster.shinyproxy.name },
      { name = "SESSION_SUBNETS", value = join(",", [data.aws_subnet.vm_subnet_1.id, data.aws_subnet.vm_subnet_2.id]) },
      { name = "SESSION_SECURITY_GROUPS", value = aws_security_group.session_sg.id },
      { name = "SESSION_EXECUTION_ROLE_ARN", value = aws_iam_role.session_execution.arn },
      { name = "VSCODE_IMAGE", value = local.vscode_image },
      { name = "RSTUDIO_IMAGE", value = local.rstudio_image },
      { name = "EFS_ID", value = data.aws_efs_file_system.efs.id },
      { name = "LDAP_URL", value = local.ldap_url },
      { name = "LDAP_BASE_DN", value = var.base_dn },
      { name = "LDAP_BIND_DN", value = local.ldap_bind_dn },
      { name = "LDAP_SECRET_ARN", value = data.aws_secretsmanager_secret.shinyproxy_ldap.arn },
    ]

    secrets = [
      { name = "LDAP_BIND_PASSWORD", valueFrom = "${data.aws_secretsmanager_secret.shinyproxy_ldap.arn}:password::" },
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.shinyproxy.name
        awslogs-region        = data.aws_region.current.region
        awslogs-stream-prefix = "shinyproxy"
      }
    }

    # ShinyProxy stops every session task on shutdown; allow it the time.
    stopTimeout = 120
  }])
}


# ================================================================================
# SECTION: ShinyProxy Service
# ================================================================================

resource "aws_ecs_service" "shinyproxy" {
  name            = "shinyproxy"
  cluster         = aws_ecs_cluster.shinyproxy.id
  task_definition = aws_ecs_task_definition.shinyproxy.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100

  # Spring Boot plus LDAP and ECS client start-up takes a while.
  health_check_grace_period_seconds = 180

  network_configuration {
    subnets          = [data.aws_subnet.vm_subnet_1.id, data.aws_subnet.vm_subnet_2.id]
    security_groups  = [aws_security_group.shinyproxy_sg.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.shinyproxy_tg.arn
    container_name   = "shinyproxy"
    container_port   = 8080
  }

  depends_on = [aws_lb_listener.https_listener]
}
