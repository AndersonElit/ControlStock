resource "kubernetes_deployment" "keycloak" {
  metadata {
    name      = "keycloak"
    namespace = "identity"
    labels    = { app = "keycloak" }
  }
  spec {
    replicas = 1
    selector {
      match_labels = { app = "keycloak" }
    }
    template {
      metadata {
        labels = { app = "keycloak" }
      }
      spec {
        container {
          name  = "keycloak"
          image = "quay.io/keycloak/keycloak:26.0"
          args  = ["start-dev"]
          port {
            container_port = 8080
            name           = "http"
          }
          env {
            name  = "KC_BOOTSTRAP_ADMIN_USERNAME"
            value = "admin"
          }
          env {
            name  = "KC_BOOTSTRAP_ADMIN_PASSWORD"
            value = var.keycloak_admin_password
          }
          env {
            name  = "KC_DB"
            value = "postgres"
          }
          env {
            name  = "KC_DB_URL"
            value = "jdbc:postgresql://postgresql.data.svc.cluster.local:5432/keycloak"
          }
          env {
            name  = "KC_DB_USERNAME"
            value = "postgres"
          }
          env {
            name  = "KC_DB_PASSWORD"
            value = var.pg_admin_password
          }
          env {
            name  = "KC_HTTP_ENABLED"
            value = "true"
          }
          resources {
            requests = {
              cpu    = "250m"
              memory = "512Mi"
            }
          }
        }
      }
    }
  }
}
resource "kubernetes_service" "keycloak" {
  metadata {
    name      = "keycloak"
    namespace = "identity"
  }
  spec {
    type     = "NodePort"
    selector = { app = "keycloak" }
    port {
      port        = 8080
      target_port = 8080
      node_port   = 8082
      name        = "http"
    }
  }
}
