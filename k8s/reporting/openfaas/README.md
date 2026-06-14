# reporting-openfaas — capa de formatos del subsistema de reportería

Generado por `report_lambdas_scaffold.py`.
OpenFaaS desplegado via Terraform Helm provider en K3s. Sin AWS Lambda ni bash deploy scripts.

## Arquitectura

```
Kafka topic: controlstock.reporting.parquet-generado  (= ReportParquetGenerated, output de report-etl-service)
       │
       ▼
helm_release.kafka_connector  [terraform/reporting/]
  (openfaas/kafka-connector via Terraform Helm provider)
       │   [HTTP POST body = mensaje Kafka]
       ▼
OpenFaaS Function: report-format-consumer  [k8s/reporting/openfaas/function/]
  (desplegada por null_resource + faas-cli en terraform/reporting/)
       │ ──► lee parquet (MinIO vía kubernetes_secret con credenciales)
       │ ──► genera CSV  → output/csv/<reportType>/<reportId>.csv
       │ ──► genera XLS  → output/xls/<reportType>/<reportId>.xlsx
       │
       └── error ──► Kafka topic: report.processing.failed

OpenFaaS Gateway  [cluster infra — base-infrastructure-builder.sh → helm-serverless]
  helm_release.openfaas  (helm-serverless module, install_openfaas = true)
```

## Prerrequisito: OpenFaaS gateway en el cluster

El gateway ya debe estar desplegado por `base-infrastructure-builder.sh` con
`install_openfaas = true`. Este módulo NO lo despliega; solo añade:
  - `kubernetes_secret` con credenciales MinIO (namespace `serverless-fn`)
  - `helm_release` kafka-connector (namespace `serverless`)
  - `null_resource` con faas-cli build + push + deploy

## Estructura generada

```
k8s/reporting/openfaas/
└── function/
    ├── handler.py      # OpenFaaS handler (python3-http)
    ├── requirements.txt
    └── stack.yml       # faas-cli: imagen, annotations topic, secrets

terraform/reporting/
├── providers.tf        # helm + kubernetes + null providers
├── variables.tf
├── main.tf             # module "openfaas_function"
├── environments/
│   └── local.tfvars
└── modules/
    └── openfaas-function/
        ├── variables.tf
        ├── main.tf     # kubernetes_secret + helm_release + null_resource
        └── deploy-function.sh  # build + push + faas-cli deploy
```

## Despliegue

```bash
# 1. Verificar que OpenFaaS gateway está corriendo (base-infrastructure-builder.sh)
kubectl get pods -n serverless

# 2. Desplegar capa de reportería
cd terraform/reporting
terraform init
terraform apply -var-file=environments/local.tfvars   -var="kubeconfig_path=/etc/rancher/k3s/k3s.yaml"   -var="minio_access_key=<key>"   -var="minio_secret_key=<secret>"   -var="openfaas_basic_auth_password=<password>"   -var="image_registry=localhost:5000"
```

## Variables sensibles

| Variable                        | Descripción                              |
|---------------------------------|------------------------------------------|
| `minio_access_key`              | Access key MinIO (sensitive)             |
| `minio_secret_key`              | Secret key MinIO (sensitive)             |
| `openfaas_basic_auth_password`  | Password del gateway OpenFaaS (sensitive)|

## Evento esperado (topic: controlstock.reporting.parquet-generado)

```json
{
  "reportId": "abc-123",
  "reportType": "cartera",
  "processedParquetUri": "s3://controlstock-reports/processed/cartera/abc-123.parquet",
  "format": "CSV"
}
```

Un evento por formato. El report-etl-service publica uno por cada formato solicitado.
