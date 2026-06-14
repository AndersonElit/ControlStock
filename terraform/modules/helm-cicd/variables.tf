variable "env"                     { type = string }
variable "vm_ip"                  { type = string }
variable "project"                { type = string }
variable "kubeconfig_path"        { type = string }
variable "gitea_admin_password" {
  type = string
  sensitive = true
}
variable "jenkins_admin_password" {
  type = string
  sensitive = true
}
variable "pg_admin_password" {
  type = string
  sensitive = true
}
