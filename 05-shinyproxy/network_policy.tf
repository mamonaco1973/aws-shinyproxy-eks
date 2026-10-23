# ================================================================================
# FILE: network_policy.tf
# ================================================================================
#
# Purpose:
#   Pod-level firewall for the ShinyProxy namespace. Every pod shares its
#   node's security group, so isolating one pod from another has to happen
#   here rather than in a security group.
#
# Rules:
#   - Session pods accept the app ports (8080, 8787) from the ShinyProxy
#     pod only. The apps run with authentication off (code-server --auth
#     none, rserver auth-none); this policy is what makes that safe - no
#     route from the ALB, and no session-to-session traffic. Do not widen it.
#   - Session pods may not reach the instance metadata endpoint, so a user
#     with sudo cannot borrow the node's IAM role.
#   - The ShinyProxy pod accepts its ports from inside the VPC: the ALB
#     (traffic, health check) and the kubelet (probes).
#
# ================================================================================


# ================================================================================
# SECTION: Enable Enforcement
# ================================================================================

# Auto Mode ships the network policy controller switched off; without this
# ConfigMap the policies below are accepted and silently ignored.
resource "kubernetes_config_map_v1" "network_policy_controller" {
  metadata {
    name      = "amazon-vpc-cni"
    namespace = "kube-system"
  }

  data = {
    enable-network-policy-controller = "true"
  }
}


# ================================================================================
# SECTION: Session Pods
# ================================================================================

resource "kubernetes_network_policy_v1" "sessions" {
  metadata {
    name      = "app-sessions"
    namespace = kubernetes_namespace_v1.shinyproxy.metadata[0].name
  }

  spec {
    # ShinyProxy labels every pod it launches with this.
    pod_selector {
      match_labels = {
        "openanalytics.eu/sp-proxied-app" = "true"
      }
    }

    policy_types = ["Ingress", "Egress"]

    ingress {
      from {
        pod_selector {
          match_labels = local.shinyproxy_labels
        }
      }

      ports {
        port     = "8080"
        protocol = "TCP"
      }

      ports {
        port     = "8787"
        protocol = "TCP"
      }
    }

    # LDAP, Open VSX and package mirrors via NAT; DNS on the node. EFS is
    # mounted by the node, not the pod, so needs no rule here.
    egress {
      to {
        ip_block {
          cidr   = "0.0.0.0/0"
          except = ["169.254.169.254/32"]
        }
      }
    }
  }

  depends_on = [kubernetes_config_map_v1.network_policy_controller]
}


# ================================================================================
# SECTION: ShinyProxy Pod
# ================================================================================

resource "kubernetes_network_policy_v1" "shinyproxy" {
  metadata {
    name      = "shinyproxy"
    namespace = kubernetes_namespace_v1.shinyproxy.metadata[0].name
  }

  spec {
    pod_selector {
      match_labels = local.shinyproxy_labels
    }

    # Egress stays open: the Kubernetes API, LDAP and the session pods.
    policy_types = ["Ingress"]

    ingress {
      from {
        ip_block {
          cidr = data.aws_vpc.ad_vpc.cidr_block
        }
      }

      ports {
        port     = "8080"
        protocol = "TCP"
      }

      ports {
        port     = "9090"
        protocol = "TCP"
      }
    }
  }

  depends_on = [kubernetes_config_map_v1.network_policy_controller]
}
