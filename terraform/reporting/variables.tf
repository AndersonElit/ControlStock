variable "kubeconfig_path"              { type = string }
variable "org"                          { type = string; default = "controlstock" }
variable "kafka_topic"                  { type = string; default = "controlstock.reporting.parquet-generado" }
variable "kafka_bootstrap"              { type = string; default = "kafka-kafka-bootstrap.messaging.svc.cluster.local:9092" }
variable "report_bucket"                { type = string; default = "controlstock-reports" }
variable "storage_endpoint"             { type = string; default = "http://minio.infra.svc.cluster.local:9000" }
variable "minio_access_key"             { type = string; sensitive = true; default = "minioadmin" }
variable "minio_secret_key"             { type = string; sensitive = true; default = "changeme_minio" }
variable "image_registry"               { type = string; default = "localhost:5000" }
variable "function_image_tag"           { type = string; default = "latest" }
variable "openfaas_gateway"             { type = string; default = "http://gateway.serverless.svc.cluster.local:8080" }
variable "openfaas_basic_auth_password" { type = string; sensitive = true; default = "changeme_openfaas" }
