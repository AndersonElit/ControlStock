variable "org"                          { type = string }
variable "kafka_topic"                  { type = string }
variable "kafka_bootstrap"              { type = string }
variable "report_bucket"                { type = string }
variable "storage_endpoint"             { type = string }
variable "minio_access_key"             { type = string; sensitive = true }
variable "minio_secret_key"             { type = string; sensitive = true }
variable "image_registry"               { type = string }
variable "function_image_tag"           { type = string; default = "latest" }
variable "openfaas_gateway"             { type = string }
variable "openfaas_basic_auth_password" { type = string; sensitive = true }
variable "kubeconfig_path"              { type = string }
