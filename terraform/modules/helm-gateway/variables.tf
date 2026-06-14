variable "install_kong" {
  type = bool
  default = true
}
variable "vm_ip"           { type = string }
variable "kubeconfig_path" { type = string }
variable "keycloak_realm"  { type = string }
