variable "vm_ip"                   { type = string }
variable "project"                 { type = string }
variable "keycloak_admin_password" {
  type = string
  sensitive = true
}
variable "pg_admin_password" {
  type = string
  sensitive = true
}
