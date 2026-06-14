# Agrega el repo Helm de OpenFaaS (idempotente).
resource "null_resource" "openfaas_helm_repo" {
  count = var.install_openfaas ? 1 : 0
  provisioner "local-exec" {
    command = "helm repo add openfaas https://openfaas.github.io/faas-netes/ 2>/dev/null || true && helm repo update"
  }
  triggers = { always = timestamp() }
}

# Secret basic-auth para el gateway (pre-creado; generateBasicAuth = false).
resource "kubernetes_secret" "openfaas_basic_auth" {
  count = var.install_openfaas ? 1 : 0
  metadata {
    name      = "basic-auth"
    namespace = "serverless"
  }
  data = {
    "basic-auth-user"     = "admin"
    "basic-auth-password" = var.openfaas_basic_auth_password
  }
}

# OpenFaaS gateway + nats + queue-worker + faas-netes operator.
# El Kafka Connector se despliega por proyecto en terraform/reporting/ (report_lambdas_scaffold.py).
resource "helm_release" "openfaas" {
  count      = var.install_openfaas ? 1 : 0
  depends_on = [null_resource.openfaas_helm_repo, kubernetes_secret.openfaas_basic_auth]

  name       = "openfaas"
  repository = "https://openfaas.github.io/faas-netes/"
  chart      = "openfaas"
  version    = "14.2.24"
  namespace  = "serverless"
  wait       = true
  timeout    = 300

    set {
    name = "functionNamespace"
    value = "serverless-fn"
  }
    set {
    name = "generateBasicAuth"
    value = "false"
  }
    set {
    name = "basic_auth"
    value = "true"
  }
    set {
    name = "operator.create"
    value = "true"
  }
    set {
    name = "operator.createCRD"
    value = "true"
  }
    set {
    name = "gateway.replicas"
    value = "1"
  }
    set {
    name = "gateway.service.type"
    value = "NodePort"
  }
    set {
    name = "gateway.service.nodePort"
    value = "31112"
  }
    set {
    name = "queueWorker.replicas"
    value = "1"
  }
    set {
    name = "nats.channel"
    value = "from-gateway"
  }
}
