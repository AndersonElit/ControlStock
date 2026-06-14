variable "install_openfaas" {
  type = bool
  default = false
}
variable "openfaas_basic_auth_password" {
  type = string
  sensitive = true
  default = "changeme_openfaas"
}
