resource "helm_release" "postgresql" {
  name       = "postgresql"
  repository = "https://charts.bitnami.com/bitnami"
  chart      = "postgresql"
  version    = "15.5.17"
  namespace  = "data"
  wait       = true
  timeout    = 300
    set_sensitive {
    name = "auth.postgresPassword"
    value = var.pg_admin_password
  }
    set {
    name = "image.tag"
    value = "latest"
  }
    set {
    name = "primary.persistence.size"
    value = "10Gi"
  }
    set {
    name = "primary.resources.requests.memory"
    value = "256Mi"
  }
    set {
    name = "primary.resources.requests.cpu"
    value = "100m"
  }
}
# Crea las bases de datos que necesitan los servicios (gitea, keycloak).
# El chart de PostgreSQL solo provee la BD 'postgres' por defecto.
resource "null_resource" "postgres_databases" {
  depends_on = [helm_release.postgresql]

  triggers = {
    databases = "gitea,keycloak"
  }

  provisioner "local-exec" {
    command = <<-CMD
      set -e
      KC="--kubeconfig=${var.kubeconfig_path}"
      echo "[INFO] Esperando PostgreSQL Ready..."
      kubectl $KC wait pod/postgresql-0 -n data --for=condition=Ready --timeout=180s
      for DB in gitea keycloak; do
        echo "[INFO] Asegurando base de datos '$DB' (idempotente)..."
        kubectl $KC exec -n data postgresql-0 -- env PGPASSWORD='${var.pg_admin_password}' \
          psql -U postgres -tc "SELECT 1 FROM pg_database WHERE datname='$DB'" \
          | grep -q 1 || \
        kubectl $KC exec -n data postgresql-0 -- env PGPASSWORD='${var.pg_admin_password}' \
          psql -U postgres -c "CREATE DATABASE \"$DB\""
      done
      echo "[OK] Bases de datos gitea y keycloak aseguradas"
    CMD
  }
}
resource "helm_release" "mongodb" {
  name       = "mongodb"
  repository = "https://charts.bitnami.com/bitnami"
  chart      = "mongodb"
  version    = "15.6.18"
  namespace  = "data"
  wait       = true
  timeout    = 300
    set_sensitive {
    name = "auth.rootPassword"
    value = var.mongo_admin_password
  }
    set {
    name = "image.tag"
    value = "latest"
  }
    set {
    name = "persistence.size"
    value = "10Gi"
  }
    set {
    name = "resources.requests.memory"
    value = "256Mi"
  }
    set {
    name = "resources.requests.cpu"
    value = "100m"
  }
}
resource "helm_release" "strimzi_operator" {
  name       = "strimzi-kafka-operator"
  repository = "https://strimzi.io/charts/"
  chart      = "strimzi-kafka-operator"
  version    = "0.40.0"
  namespace  = "messaging"
  wait       = true
  timeout    = 300
}
# Kafka CRs aplicados después de que el operator instale los CRDs
resource "null_resource" "kafka_cluster" {
  depends_on = [helm_release.strimzi_operator]
  provisioner "local-exec" {
    command = "kubectl --kubeconfig='${var.kubeconfig_path}' apply -n messaging -f '${path.module}/kafka-cluster.yaml'"
  }
  triggers = { strimzi_version = helm_release.strimzi_operator.version }
}
