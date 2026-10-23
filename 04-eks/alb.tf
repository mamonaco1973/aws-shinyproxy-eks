# ================================================================================
# FILE: alb.tf
# ================================================================================
#
# Purpose:
#   Public HTTPS entry point. Terminates TLS and forwards to the single
#   ShinyProxy pod, which in turn proxies to each user's session pod.
#
# Design Notes:
#   - The ALB and its target group belong to Terraform, not to a Kubernetes
#     Ingress, so the self-signed certificate (acm.tf) can be issued for the
#     ALB's DNS name before anything runs in the cluster. Phase 05 binds the
#     target group to the ShinyProxy Service with a TargetGroupBinding, and
#     Auto Mode's load balancer controller keeps the pod's IP registered.
#   - target_type = "ip": pods register by their VPC address, so traffic
#     goes straight to the pod rather than through a node port.
#   - idle_timeout is raised to an hour: the editor rides on one long-lived
#     WebSocket, and the 60 s default drops it whenever the user pauses.
#   - No stickiness. There is one ShinyProxy pod, and a session's identity
#     lives in ShinyProxy's session cookie, not in which target served it.
#
# ================================================================================

resource "aws_lb" "shinyproxy_alb" {
  name               = "shinyproxy-eks-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  idle_timeout       = 3600

  subnets = [
    data.aws_subnet.pub_subnet_1.id,
    data.aws_subnet.pub_subnet_2.id
  ]
}

# Phase 05 looks the target group up by this name.
resource "aws_lb_target_group" "shinyproxy_tg" {
  name        = "shinyproxy-eks-tg"
  port        = 8080
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = data.aws_vpc.ad_vpc.id

  # ShinyProxy stops every session on shutdown; give in-flight requests a
  # moment, not the 300 s default.
  deregistration_delay = 15

  health_check {
    port                = "9090"
    path                = "/actuator/health"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
    matcher             = "200"
  }
}

resource "aws_lb_listener" "http_listener" {
  load_balancer_arn = aws_lb.shinyproxy_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_lb_listener" "https_listener" {
  load_balancer_arn = aws_lb.shinyproxy_alb.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate.alb.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.shinyproxy_tg.arn
  }
}
