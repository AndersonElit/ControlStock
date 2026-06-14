variable "pg_admin_password" {
  type = string
  sensitive = true
}
variable "mongo_admin_password" {
  type = string
  sensitive = true
}
variable "kubeconfig_path"      { type = string }
