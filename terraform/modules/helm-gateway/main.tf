# Añadir repo Kong a Helm antes de usar este módulo:
#   helm repo add kong https://charts.konghq.com && helm repo update

resource "helm_release" "kong" {
  count = var.install_kong ? 1 : 0

  name       = "kong"
  repository = "https://charts.konghq.com"
  chart      = "kong"
  version    = "2.38.0"
  namespace  = "gateway"
  wait       = true
  timeout    = 300

  values = [<<-YAML
    # Modo DB-less: no requiere PostgreSQL
    env:
      database: "off"

    # Proxy (entrada de tráfico de usuarios)
    proxy:
      type: NodePort
      http:
        enabled: true
        nodePort: 8000
      tls:
        enabled: false

    # Admin API (solo ClusterIP — no exponer al exterior)
    admin:
      enabled: true
      type: ClusterIP
      http:
        enabled: true

    # Ingress Controller (gestión de rutas via KongIngress / HTTPRoute)
    ingressController:
      enabled: true
      # Las CRDs ya las instala Helm desde el directorio crds/ del chart.
      # Con installCRDs:true se renderizan además como plantillas y chocan
      # con las del crds/ (que no tienen ownership de Helm) -> install falla.
      installCRDs: false
      env:
        kong_admin_url: http://localhost:8001

    resources:
      requests:
        memory: 256Mi
        cpu:    100m
      limits:
        memory: 512Mi
        cpu:    "500m"
  YAML
  ]
}

# Agregar repo Kong al cluster (necesario antes del apply)
resource "null_resource" "kong_helm_repo" {
  count      = var.install_kong ? 1 : 0
  depends_on = []

  provisioner "local-exec" {
    command = <<-CMD
      helm --kubeconfig='${var.kubeconfig_path}' repo add kong https://charts.konghq.com 2>/dev/null || true
      helm --kubeconfig='${var.kubeconfig_path}' repo update
    CMD
  }
  triggers = { always = timestamp() }
}

# Configurar Kong con JWT plugin + clave pública Keycloak
resource "null_resource" "kong_keycloak_setup" {
  count      = var.install_kong ? 1 : 0
  depends_on = [helm_release.kong]

  provisioner "local-exec" {
    command = <<-CMD
      bash '${path.module}/kong-keycloak-setup.sh' \
        '${var.kubeconfig_path}' \
        'http://keycloak.identity.svc.cluster.local:8080' \
        '${var.keycloak_realm}'
    CMD
  }
  triggers = {
    kong_version   = var.install_kong ? helm_release.kong[0].version : "disabled"
    keycloak_realm = var.keycloak_realm
  }
}
