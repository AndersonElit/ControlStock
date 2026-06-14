#!/usr/bin/env bash
# Construye y despliega la función report-format-consumer en OpenFaaS.
# Invocado por null_resource.deploy_function (Terraform) con las variables
# OPENFAAS_BASIC_AUTH_PASSWORD inyectadas como env por Terraform.
set -euo pipefail

REGISTRY="$1"
ORG="$2"
IMAGE_TAG="${3:-latest}"
GATEWAY="$4"

FUNCTION_DIR="$(cd "$(dirname "$0")/../../../k8s/reporting/openfaas/function" && pwd)"

echo "[INFO] Instalando template python3-http..."
OPENFAAS_URL="${GATEWAY}" faas-cli template store pull python3-http 2>/dev/null || true

echo "[INFO] Build imagen ${REGISTRY}/${ORG}/report-format-consumer:${IMAGE_TAG}..."
OPENFAAS_URL="${GATEWAY}" faas-cli build -f "${FUNCTION_DIR}/stack.yml"

echo "[INFO] Push imagen..."
OPENFAAS_URL="${GATEWAY}" faas-cli push -f "${FUNCTION_DIR}/stack.yml"

echo "[INFO] Login en OpenFaaS gateway ${GATEWAY}..."
echo "${OPENFAAS_BASIC_AUTH_PASSWORD}"   | OPENFAAS_URL="${GATEWAY}" faas-cli login --username admin --password-stdin

echo "[INFO] Deploy función report-format-consumer..."
OPENFAAS_URL="${GATEWAY}" faas-cli deploy -f "${FUNCTION_DIR}/stack.yml"

echo "[OK] report-format-consumer desplegada en ${GATEWAY}"
echo "     Escuchando topic: controlstock.reporting.parquet-generado"
