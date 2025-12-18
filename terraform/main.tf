# Persistent Volume Claim
resource "kubernetes_persistent_volume_claim" "nexus_pvc" {
  metadata {
    name      = "nexus-pvc"
    namespace = "build"
  }

  spec {
    access_modes = ["ReadWriteOnce"]

    resources {
      requests = {
        storage = "5Gi"
      }
    }
  }
}

# Nexus Deployment
resource "kubernetes_deployment" "nexus" {
  metadata {
    name      = "nexus"
    namespace = "build"
    labels = {
      app = "nexus"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "nexus"
      }
    }

    template {
      metadata {
        labels = {
          app = "nexus"
        }
      }

      spec {
        container {
          name  = "nexus"
          image = "sonatype/nexus3:latest"

          port {
            container_port = 8081
          }

          volume_mount {
            name       = "nexus-data"
            mount_path = "/nexus-data"
          }
        }

        volume {
          name = "nexus-data"

          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.nexus_pvc.metadata[0].name
          }
        }
      }
    }
  }
}

# Nexus Service
resource "kubernetes_service" "nexus" {
  metadata {
    name      = "nexus-service"
    namespace = "build"
  }

  spec {
    selector = {
      app = kubernetes_deployment.nexus.metadata[0].labels.app
    }

    port {
      port        = 8081
      target_port = 8081
    }

    type = "NodePort"
  }
}
