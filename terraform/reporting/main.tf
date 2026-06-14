module "openfaas_function" {
  source = "./modules/openfaas-function"

  org                          = var.org
  kafka_topic                  = var.kafka_topic
  kafka_bootstrap              = var.kafka_bootstrap
  report_bucket                = var.report_bucket
  storage_endpoint             = var.storage_endpoint
  minio_access_key             = var.minio_access_key
  minio_secret_key             = var.minio_secret_key
  image_registry               = var.image_registry
  function_image_tag           = var.function_image_tag
  openfaas_gateway             = var.openfaas_gateway
  openfaas_basic_auth_password = var.openfaas_basic_auth_password
  kubeconfig_path              = var.kubeconfig_path
}
