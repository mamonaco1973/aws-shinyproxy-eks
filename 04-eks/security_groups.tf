# ================================================================================
# FILE: security_groups.tf
# ================================================================================
#
# Purpose:
#   Traffic path: Internet -> ALB -> ShinyProxy pod -> session pod.
#
# Design Notes:
#   - Auto Mode nodes, and so every pod on them, carry the cluster security
#     group EKS creates. Only the first hop is a security group rule: the
#     ALB may reach that group on ShinyProxy's ports (8080 for traffic,
#     9090 for the health check).
#   - Pods share their node's security group, so session isolation cannot
#     be a security group here. Session pods run their app with
#     authentication off (code-server --auth none, rserver auth-none), and
#     phase 05's NetworkPolicy admits the app ports from the ShinyProxy pod
#     alone - no ALB route, and no session-to-session traffic. Do not widen
#     it.
#
# ================================================================================

resource "aws_security_group" "alb_sg" {
  name        = "shinyproxy-eks-alb-sg"
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

resource "aws_vpc_security_group_ingress_rule" "alb_to_shinyproxy" {
  for_each = {
    "8080" = "ShinyProxy (TCP 8080) from ALB"
    "9090" = "ShinyProxy management/health (TCP 9090) from ALB"
  }

  security_group_id            = aws_eks_cluster.shinyproxy.vpc_config[0].cluster_security_group_id
  referenced_security_group_id = aws_security_group.alb_sg.id
  description                  = each.value
  ip_protocol                  = "tcp"
  from_port                    = tonumber(each.key)
  to_port                      = tonumber(each.key)
}
