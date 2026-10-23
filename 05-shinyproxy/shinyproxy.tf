# ================================================================================
# FILE: shinyproxy.tf
# ================================================================================
#
# Purpose:
#   The ShinyProxy namespace, its permissions, and ShinyProxy itself, bound
#   to the ALB target group phase 04 built.
#
# Session Pods:
#   Not defined here. ShinyProxy creates a pod per session (sp-pod-<proxy
#   id>-0) in this namespace through the Kubernetes API, and deletes it when
#   the session ends. Their shape comes from the specs in
#   03-images/shinyproxy/application.yml.
#
# Design Notes:
#   - One ShinyProxy pod. ShinyProxy holds session state in memory: a
#     restart stops every session, which ShinyProxy does deliberately on
#     shutdown rather than orphan pods. Running two would need Redis
#     (proxy.store-mode: Redis).
#   - Recreate strategy, so the old ShinyProxy is gone before the new one
#     starts - two instances must never manage the same sessions at once.
#   - do-not-disrupt keeps Auto Mode from moving ShinyProxy (and with it
#     every session) to consolidate nodes.
#
# ================================================================================

resource "kubernetes_namespace_v1" "shinyproxy" {
  metadata {
    name = local.namespace
  }
}


# ================================================================================
# SECTION: LDAP Bind Password
# ================================================================================

# Read by ShinyProxy for its own LDAP searches, and handed to each session
# pod by reference (secretKeyRef in application.yml) - ShinyProxy never
# copies the value into a pod spec.
resource "kubernetes_secret_v1" "ldap_bind" {
  metadata {
    name      = "ldap-bind"
    namespace = kubernetes_namespace_v1.shinyproxy.metadata[0].name
  }

  data = {
    password = jsondecode(data.aws_secretsmanager_secret_version.shinyproxy_ldap.secret_string)["password"]
  }
}


# ================================================================================
# SECTION: ShinyProxy Permissions
# ================================================================================

# Namespace-scoped: ShinyProxy can manage pods here and nowhere else.
resource "kubernetes_service_account_v1" "shinyproxy" {
  metadata {
    name      = "shinyproxy"
    namespace = kubernetes_namespace_v1.shinyproxy.metadata[0].name
  }
}

resource "kubernetes_role_v1" "shinyproxy" {
  metadata {
    name      = "shinyproxy"
    namespace = kubernetes_namespace_v1.shinyproxy.metadata[0].name
  }

  # Session pods: create, watch until ready, delete.
  rule {
    api_groups = [""]
    resources  = ["pods"]
    verbs      = ["get", "list", "watch", "create", "delete", "patch"]
  }

  rule {
    api_groups = [""]
    resources  = ["pods/log"]
    verbs      = ["get"]
  }

  # The headless service ShinyProxy keeps for its session pods.
  rule {
    api_groups = [""]
    resources  = ["services"]
    verbs      = ["get", "list", "create", "delete"]
  }

  # Read to report why a pod failed to start.
  rule {
    api_groups = [""]
    resources  = ["events"]
    verbs      = ["get", "list", "watch"]
  }
}

resource "kubernetes_role_binding_v1" "shinyproxy" {
  metadata {
    name      = "shinyproxy"
    namespace = kubernetes_namespace_v1.shinyproxy.metadata[0].name
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role_v1.shinyproxy.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.shinyproxy.metadata[0].name
    namespace = kubernetes_namespace_v1.shinyproxy.metadata[0].name
  }
}


# ================================================================================
# SECTION: ShinyProxy Deployment
# ================================================================================

resource "kubernetes_deployment_v1" "shinyproxy" {
  metadata {
    name      = "shinyproxy"
    namespace = kubernetes_namespace_v1.shinyproxy.metadata[0].name
    labels    = local.shinyproxy_labels
  }

  spec {
    replicas = 1

    strategy {
      type = "Recreate"
    }

    selector {
      match_labels = local.shinyproxy_labels
    }

    template {
      metadata {
        labels = local.shinyproxy_labels

        annotations = {
          "karpenter.sh/do-not-disrupt" = "true"
        }
      }

      spec {
        service_account_name = kubernetes_service_account_v1.shinyproxy.metadata[0].name

        node_selector = {
          "kubernetes.io/arch" = "amd64"
        }

        # ShinyProxy deletes every session pod on shutdown; allow it the time.
        termination_grace_period_seconds = 120

        container {
          name  = "shinyproxy"
          image = local.shinyproxy_image

          port {
            name           = "http"
            container_port = 8080
          }

          port {
            name           = "management"
            container_port = 9090
          }

          # Resolved into application.yml's ${...} placeholders by Spring.
          env {
            name  = "SESSION_NAMESPACE"
            value = kubernetes_namespace_v1.shinyproxy.metadata[0].name
          }
          env {
            name  = "VSCODE_IMAGE"
            value = local.vscode_image
          }
          env {
            name  = "RSTUDIO_IMAGE"
            value = local.rstudio_image
          }
          env {
            name  = "LDAP_URL"
            value = local.ldap_url
          }
          env {
            name  = "LDAP_BASE_DN"
            value = var.base_dn
          }
          env {
            name  = "LDAP_BIND_DN"
            value = local.ldap_bind_dn
          }
          env {
            name = "LDAP_BIND_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.ldap_bind.metadata[0].name
                key  = "password"
              }
            }
          }

          resources {
            requests = {
              cpu    = "1"
              memory = "2Gi"
            }
            limits = {
              memory = "2Gi"
            }
          }

          readiness_probe {
            http_get {
              path = "/actuator/health"
              port = "management"
            }
            period_seconds    = 10
            failure_threshold = 3
          }

          # Spring Boot plus LDAP and Kubernetes client start-up takes a
          # while; a restart signs everyone out, so be slow to give up.
          liveness_probe {
            http_get {
              path = "/actuator/health"
              port = "management"
            }
            initial_delay_seconds = 180
            period_seconds        = 20
            failure_threshold     = 6
          }
        }
      }
    }
  }

  # Session pods mount the claim, are policed by the policies and run in the
  # sessions node pool; all must exist before ShinyProxy can start one.
  depends_on = [
    kubernetes_role_binding_v1.shinyproxy,
    kubernetes_persistent_volume_claim_v1.efs,
    kubernetes_network_policy_v1.sessions,
    kubernetes_manifest.session_node_pool,
  ]
}

resource "kubernetes_service_v1" "shinyproxy" {
  metadata {
    name      = "shinyproxy"
    namespace = kubernetes_namespace_v1.shinyproxy.metadata[0].name
  }

  spec {
    selector = local.shinyproxy_labels

    port {
      name        = "http"
      port        = 8080
      target_port = "http"
    }
  }
}


# ================================================================================
# SECTION: ALB Target Group Binding
# ================================================================================

# Auto Mode's load balancer controller registers the ShinyProxy pod's IP
# in phase 04's target group, and swaps it when the pod is replaced. The
# ALB health check (port 9090) is configured on the target group itself.
resource "kubernetes_manifest" "shinyproxy_target_group_binding" {
  manifest = {
    apiVersion = "eks.amazonaws.com/v1"
    kind       = "TargetGroupBinding"

    metadata = {
      name      = "shinyproxy"
      namespace = kubernetes_namespace_v1.shinyproxy.metadata[0].name
    }

    spec = {
      targetGroupARN = data.aws_lb_target_group.shinyproxy.arn
      targetType     = "ip"

      serviceRef = {
        name = kubernetes_service_v1.shinyproxy.metadata[0].name
        port = 8080
      }
    }
  }
}


# ================================================================================
# SECTION: Outputs
# ================================================================================

output "namespace" {
  value = kubernetes_namespace_v1.shinyproxy.metadata[0].name
}
