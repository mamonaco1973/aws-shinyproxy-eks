# ================================================================================
# FILE: security_groups.tf
# ================================================================================
#
# Purpose:
#   Three-tier traffic path: Internet -> ALB -> ShinyProxy -> session task.
#
# Design Notes:
#   - Session tasks run their app with authentication off (code-server
#     --auth none, rserver auth-none). That is safe only because session_sg
#     admits the app ports from ShinyProxy alone - no ALB route, and no
#     session-to-session traffic. Do not widen it.
#   - ShinyProxy's management port (9090) serves the ALB health check.
#
# ================================================================================

resource "aws_security_group" "alb_sg" {
  name        = "shinyproxy-alb-sg"
  description = "Allow HTTP (redirect) and HTTPS to the ALB"
  vpc_id      = data.aws_vpc.ad_vpc.id

  ingress {
    description = "HTTP (TCP 80) for redirect to HTTPS"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS (TCP 443)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "shinyproxy_sg" {
  name        = "shinyproxy-sg"
  description = "Allow ShinyProxy traffic and health checks from the ALB"
  vpc_id      = data.aws_vpc.ad_vpc.id

  ingress {
    description     = "ShinyProxy (TCP 8080) from ALB"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  ingress {
    description     = "ShinyProxy management/health (TCP 9090) from ALB"
    from_port       = 9090
    to_port         = 9090
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  # Egress: ECS and ECR APIs via NAT, LDAP to the DC, 8080 to sessions.
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "session_sg" {
  name        = "app-session-sg"
  description = "Allow app ports from ShinyProxy only"
  vpc_id      = data.aws_vpc.ad_vpc.id

  ingress {
    description     = "code-server (TCP 8080) from ShinyProxy"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.shinyproxy_sg.id]
  }

  ingress {
    description     = "RStudio Server (TCP 8787) from ShinyProxy"
    from_port       = 8787
    to_port         = 8787
    protocol        = "tcp"
    security_groups = [aws_security_group.shinyproxy_sg.id]
  }

  # Egress: EFS, LDAP, Open VSX and package mirrors via NAT.
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
