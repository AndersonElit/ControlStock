resource "kubernetes_deployment" "lra_coordinator" {
  count = var.install_lra ? 1 : 0
  metadata {
    name      = "lra-coordinator"
    namespace = "infra"
    labels    = { app = "lra-coordinator" }
  }
  spec {
    replicas = 1
    selector { match_labels = { app = "lra-coordinator" } }
    template {
      metadata { labels = { app = "lra-coordinator" } }
      spec {
        container {
          name  = "lra-coordinator"
          image = "quay.io/jbosstm/lra-coordinator:latest"
          port  { container_port = 8080 }
                    env {
            name = "QUARKUS_HTTP_PORT"
            value = "8080"
          }
                    resources {
            requests = { memory = "128Mi"
            cpu = "100m" }
          }
        }
      }
    }
  }
}
resource "kubernetes_service" "lra_coordinator" {
  count      = var.install_lra ? 1 : 0
  depends_on = [kubernetes_deployment.lra_coordinator]
    metadata {
    name = "lra-coordinator"
    namespace = "infra"
  }
  spec {
    type     = "NodePort"
    selector = { app = "lra-coordinator" }
        port {
      port = 8080
      target_port = 8080
      node_port = 50000
    }
  }
}
resource "kubernetes_deployment" "wiremock" {
  count = var.install_wiremock ? 1 : 0
  metadata {
    name      = "wiremock"
    namespace = "infra"
    labels    = { app = "wiremock" }
  }
  spec {
    replicas = 1
    selector { match_labels = { app = "wiremock" } }
    template {
      metadata { labels = { app = "wiremock" } }
      spec {
        container {
          name  = "wiremock"
          image = "wiremock/wiremock:3x"
          args  = ["--port=9999", "--verbose"]
          port  { container_port = 9999 }
                    resources {
            requests = { memory = "128Mi"
            cpu = "100m" }
          }
        }
      }
    }
  }
}
resource "kubernetes_service" "wiremock" {
  count      = var.install_wiremock ? 1 : 0
  depends_on = [kubernetes_deployment.wiremock]
    metadata {
    name = "wiremock"
    namespace = "infra"
  }
  spec {
    type     = "NodePort"
    selector = { app = "wiremock" }
        port {
      port = 9999
      target_port = 9999
      node_port = 9999
    }
  }
}
