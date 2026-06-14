resource "helm_release" "traefik" {
  name       = "traefik"
  repository = "https://helm.traefik.io/traefik"
  chart      = "traefik"
  version    = "28.3.0"
  namespace  = "infra"
  wait       = true
  timeout    = 180
    set {
    name = "deployment.replicas"
    value = "1"
  }
    set {
    name = "ports.web.exposedPort"
    value = "80"
  }
    set {
    name = "ports.websecure.exposedPort"
    value = "443"
  }
    set {
    name = "service.type"
    value = "NodePort"
  }
    set {
    name = "ports.traefik.expose.default"
    value = "true"
  }
}
resource "helm_release" "cert_manager" {
  name       = "cert-manager"
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  version    = "v1.14.5"
  namespace  = "infra"
  wait       = true
  timeout    = 180
    set {
    name = "installCRDs"
    value = "true"
  }
    set {
    name = "resources.requests.memory"
    value = "64Mi"
  }
}
resource "helm_release" "minio" {
  count      = var.install_minio ? 1 : 0
  name       = "minio"
  repository = "https://charts.min.io/"
  chart      = "minio"
  version    = "5.4.0"
  namespace  = "infra"
  wait       = true
  timeout    = 300
    set {
    name = "rootUser"
    value = "minioadmin"
  }
    set_sensitive {
    name = "rootPassword"
    value = var.minio_root_password
  }
    set {
    name = "mode"
    value = "standalone"
  }
    set {
    name = "persistence.size"
    value = "10Gi"
  }
    set {
    name = "service.type"
    value = "NodePort"
  }
    set {
    name = "service.nodePorts.api"
    value = "9000"
  }
    set {
    name = "service.nodePorts.console"
    value = "9001"
  }
    set {
    name = "resources.requests.memory"
    value = "256Mi"
  }
    set {
    name = "environment.MINIO_DEFAULT_BUCKETS"
    value = "${var.project}-reports"
  }
}
