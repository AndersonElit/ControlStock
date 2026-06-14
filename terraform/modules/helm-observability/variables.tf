variable "grafana_admin_password" {
  type = string
  sensitive = true
}
variable "install_loki" {
  type = bool
  default = true
}
variable "install_tempo" {
  type = bool
  default = true
}
