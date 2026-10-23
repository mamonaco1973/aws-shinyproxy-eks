# ================================================================================
# FILE: node_pool.tf
# ================================================================================
#
# Purpose:
#   An Auto Mode node pool reserved for session pods, built from 8 vCPU
#   instances so several sessions share one node.
#
# Why a separate pool:
#   Auto Mode launches the cheapest instance that fits the one pod it is
#   waiting on. In the built-in general-purpose pool that is a 2 vCPU node
#   per 1 vCPU session, and do-not-disrupt (rightly) stops it repacking them
#   later - so every session ended up with a node of its own. Here the first
#   session buys an 8 vCPU node and the next ones start on it in seconds,
#   with the image already pulled.
#
# Design Notes:
#   - Same instance rules as general-purpose (on-demand c/m/r, generation
#     5+, amd64), narrowed to 8 vCPU. c-family 8 vCPU nodes have too little
#     memory for the 16 GiB session, so that one lands on m or r.
#   - The taint keeps everything else off: only pods that tolerate it -
#     the session pods (application.yml) and DaemonSets such as the EFS
#     CSI node plugin - run here. ShinyProxy stays in general-purpose.
#   - WhenEmpty: a node goes only once its last session has ended, five
#     minutes later, so a user who signs straight back in gets a warm node.
#   - The CPU limit caps the pool at four nodes.
#   - Uses the built-in "default" NodeClass (subnets, security group, node
#     role), which exists because the built-in pools are enabled.
#
# ================================================================================

resource "kubernetes_manifest" "session_node_pool" {
  manifest = {
    apiVersion = "karpenter.sh/v1"
    kind       = "NodePool"

    metadata = {
      name = "sessions"
    }

    spec = {
      template = {
        spec = {
          nodeClassRef = {
            group = "eks.amazonaws.com"
            kind  = "NodeClass"
            name  = "default"
          }

          requirements = [
            { key = "karpenter.sh/capacity-type", operator = "In", values = ["on-demand"] },
            { key = "eks.amazonaws.com/instance-category", operator = "In", values = ["c", "m", "r"] },
            { key = "eks.amazonaws.com/instance-generation", operator = "Gt", values = ["4"] },
            { key = "eks.amazonaws.com/instance-cpu", operator = "In", values = ["8"] },
            { key = "kubernetes.io/arch", operator = "In", values = ["amd64"] },
          ]

          # Referenced by the session pod patches in application.yml.
          taints = [
            { key = "shinyproxy/session", value = "true", effect = "NoSchedule" },
          ]

          expireAfter = "336h"
        }
      }

      disruption = {
        consolidationPolicy = "WhenEmpty"
        consolidateAfter    = "5m"
      }

      limits = {
        cpu = "32"
      }
    }
  }
}
