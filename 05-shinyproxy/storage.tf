# ================================================================================
# FILE: storage.tf
# ================================================================================
#
# Purpose:
#   Present the shared EFS file system to the cluster as one static
#   PersistentVolume, claimed once in the ShinyProxy namespace. Every session
#   pod mounts that claim twice (see the pod patches in application.yml):
#     - subPath home  -> /home
#     - the root      -> /efs
#   matching the layout the Samba gateway mounts.
#
# Design Notes:
#   - Static, not dynamically provisioned: the file system already exists
#     (phase 02) and is shared with the gateway, so the CSI driver only
#     mounts it. No access point - sessions start as root and set their own
#     ownership, as on the EC2 hosts.
#   - Retain: deleting the PersistentVolume never touches the data.
#   - The capacity is a required field with no effect; EFS is elastic.
#
# ================================================================================

resource "kubernetes_persistent_volume_v1" "efs" {
  metadata {
    name = "shinyproxy-eks-efs"
  }

  spec {
    capacity = {
      storage = "1Ti"
    }
    access_modes                     = ["ReadWriteMany"]
    persistent_volume_reclaim_policy = "Retain"
    storage_class_name               = ""

    persistent_volume_source {
      csi {
        driver        = "efs.csi.aws.com"
        volume_handle = data.aws_efs_file_system.efs.id

        volume_attributes = {
          encryptInTransit = "true"
        }
      }
    }
  }
}

# The name "efs" is referenced by the session pod patches in application.yml.
resource "kubernetes_persistent_volume_claim_v1" "efs" {
  metadata {
    name      = "efs"
    namespace = kubernetes_namespace_v1.shinyproxy.metadata[0].name
  }

  spec {
    access_modes       = ["ReadWriteMany"]
    storage_class_name = ""
    volume_name        = kubernetes_persistent_volume_v1.efs.metadata[0].name

    resources {
      requests = {
        storage = "1Ti"
      }
    }
  }
}
