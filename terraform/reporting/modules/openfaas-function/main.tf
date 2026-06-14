# Secrets MinIO montados por OpenFaaS en /var/openfaas/secrets/<name>
resource "kubernetes_secret" "minio_access_key" {
  metadata {
    name      = "report-minio-access-key"
    namespace = "serverless-fn"
  }
  data = { "report-minio-access-key" = var.minio_access_key }
}

resource "kubernetes_secret" "minio_secret_key" {
  metadata {
    name      = "report-minio-secret-key"
    namespace = "serverless-fn"
  }
  data = { "report-minio-secret-key" = var.minio_secret_key }
}

# Helm repo OpenFaaS (idempotente — mismo repo que usa base-infrastructure-builder.sh)
resource "null_resource" "openfaas_helm_repo" {
  provisioner "local-exec" {
    command = "helm repo add openfaas https://openfaas.github.io/faas-netes/ 2>/dev/null || true && helm repo update"
  }
  triggers = { always = timestamp() }
}

# Kafka Connector — bridge Strimzi (messaging ns) → función OpenFaaS
# El connector enruta automáticamente los mensajes del topic a las funciones
# que tienen la anotación `topic: <kafka_topic>` en su stack.yml.
resource "helm_release" "kafka_connector" {
  depends_on = [null_resource.openfaas_helm_repo]

  name       = "kafka-connector"
  repository = "https://openfaas.github.io/faas-netes/"
  chart      = "kafka-connector"
  namespace  = "serverless"
  wait       = true
  timeout    = 120

  set { name = "topics";           value = var.kafka_topic }
  set { name = "broker.host";      value = split(":", var.kafka_bootstrap)[0] }
  set { name = "broker.port";      value = split(":", var.kafka_bootstrap)[1] }
  set { name = "gatewayURL";       value = var.openfaas_gateway }
  set { name = "upstreamTimeout";  value = "300s" }
  set { name = "asyncInvocation";  value = "false" }
  set { name = "contentType";      value = "application/json" }
  set { name = "printResponse";    value = "true" }
  set { name = "basicAuth";        value = "true" }
  set_sensitive { name = "basicAuthPassword"; value = var.openfaas_basic_auth_password }
}

# Deploy función via faas-cli (build + push + deploy)
# Se re-ejecuta cuando cambia image_tag, topic o gateway.
resource "null_resource" "deploy_function" {
  depends_on = [
    helm_release.kafka_connector,
    kubernetes_secret.minio_access_key,
    kubernetes_secret.minio_secret_key,
  ]

  provisioner "local-exec" {
    command = <<-CMD
      bash '${path.module}/deploy-function.sh'         '${var.image_registry}'         '${var.org}'         '${var.function_image_tag}'         '${var.openfaas_gateway}'
    CMD
    environment = {
      OPENFAAS_BASIC_AUTH_PASSWORD = var.openfaas_basic_auth_password
    }
  }

  triggers = {
    image_tag   = var.function_image_tag
    kafka_topic = var.kafka_topic
    gateway     = var.openfaas_gateway
  }
}
