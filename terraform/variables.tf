variable "kubeconfig_path"          { type = string }
variable "vm_ip"                    { type = string }
variable "project"                  { type = string }
variable "env" {
  type = string
  default = "local"
}
variable "pg_admin_password" {
  type = string
  sensitive = true
  default = "changeme_pg_admin"
}
variable "mongo_admin_password" {
  type = string
  sensitive = true
  default = "changeme_mongo_admin"
}
variable "keycloak_admin_password" {
  type = string
  sensitive = true
  default = "changeme_kc_admin"
}
variable "gitea_admin_password" {
  type = string
  sensitive = true
  default = "changeme_gitea_admin"
}
variable "jenkins_admin_password" {
  type = string
  sensitive = true
  default = "changeme_jenkins_admin"
}
variable "grafana_admin_password" {
  type = string
  sensitive = true
  default = "changeme_grafana_admin"
}
variable "install_lra" {
  type = bool
  default = true
}
variable "install_wiremock" {
  type = bool
  default = true
}
variable "install_loki" {
  type = bool
  default = true
}
variable "install_tempo" {
  type = bool
  default = true
}
variable "install_kong" {
  type = bool
  default = true
}
variable "keycloak_realm" {
  type = string
  default = ""
}
variable "minio_root_password" {
  type = string
  sensitive = true
  default = "changeme_minio"
}
variable "install_minio" {
  type = bool
  default = true
}
variable "install_openfaas" {
  type = bool
  default = false
}
variable "openfaas_basic_auth_password" {
  type = string
  sensitive = true
  default = "changeme_openfaas"
}
