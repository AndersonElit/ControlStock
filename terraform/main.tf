module "namespaces" {
  source = "./modules/namespaces"
}

module "helm_infra" {
  source              = "./modules/helm-infra"
  depends_on          = [module.namespaces]
  project             = var.project
  install_minio       = var.install_minio
  minio_root_password = var.minio_root_password
}

module "helm_data" {
  source               = "./modules/helm-data"
  depends_on           = [module.namespaces]
  pg_admin_password    = var.pg_admin_password
  mongo_admin_password = var.mongo_admin_password
  kubeconfig_path      = var.kubeconfig_path
}

module "helm_identity" {
  source                  = "./modules/helm-identity"
  depends_on              = [module.helm_data]
  vm_ip                   = var.vm_ip
  project                 = var.project
  keycloak_admin_password = var.keycloak_admin_password
  pg_admin_password       = var.pg_admin_password
}

module "helm_secrets" {
  source          = "./modules/helm-secrets"
  depends_on      = [module.namespaces]
  kubeconfig_path = var.kubeconfig_path
}

module "helm_cicd" {
  source                 = "./modules/helm-cicd"
  depends_on             = [module.helm_data, module.helm_secrets]
  env                    = var.env
  vm_ip                  = var.vm_ip
  project                = var.project
  kubeconfig_path        = var.kubeconfig_path
  gitea_admin_password   = var.gitea_admin_password
  jenkins_admin_password = var.jenkins_admin_password
  pg_admin_password      = var.pg_admin_password
}

module "helm_observability" {
  source                 = "./modules/helm-observability"
  depends_on             = [module.namespaces]
  grafana_admin_password = var.grafana_admin_password
  install_loki           = var.install_loki
  install_tempo          = var.install_tempo
}

module "helm_support" {
  source           = "./modules/helm-support"
  depends_on       = [module.helm_infra]
  install_lra      = var.install_lra
  install_wiremock = var.install_wiremock
}

# ── API Gateway: Kong (depende de Keycloak para OIDC/JWT) ─────────────────────
module "helm_gateway" {
  source          = "./modules/helm-gateway"
  depends_on      = [module.helm_identity]
  install_kong    = var.install_kong
  vm_ip           = var.vm_ip
  kubeconfig_path = var.kubeconfig_path
  keycloak_realm  = var.keycloak_realm != "" ? var.keycloak_realm : var.project
}

# ── Serverless: OpenFaaS gateway (opcional; Kafka Connector se despliega por proyecto) ──
module "helm_serverless" {
  source                       = "./modules/helm-serverless"
  depends_on                   = [module.namespaces]
  install_openfaas             = var.install_openfaas
  openfaas_basic_auth_password = var.openfaas_basic_auth_password
}
