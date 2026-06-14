variable "project"             { type = string }
variable "install_minio" {
  type = bool
  default = true
}
variable "minio_root_password" {
  type = string
  sensitive = true
  default = "changeme_minio"
}
