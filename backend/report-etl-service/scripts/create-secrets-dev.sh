#!/usr/bin/env bash
# Crea/actualiza el secret de desarrollo en HashiCorp Vault (K3s).
# Uso: KUBECONFIG=~/.kube/config-controlstock-local bash scripts/create-secrets-dev.sh
# Requiere que Vault esté unsealed y vault-init.json esté disponible.

set -euo pipefail
KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config-controlstock-local}"
SECRET_PATH="controlstock/dev/report-etl-service"
INIT_FILE="${VAULT_INIT_FILE:-./vault-init.json}"

if [[ -f "$INIT_FILE" ]]; then
    VAULT_TOKEN=$(python3 -c "import json; print(json.load(open('$INIT_FILE'))['root_token'])" 2>/dev/null \
        || jq -r '.root_token' "$INIT_FILE" 2>/dev/null)
fi
VAULT_TOKEN="${VAULT_TOKEN:-${VAULT_ROOT_TOKEN:-}}"
[[ -z "$VAULT_TOKEN" ]] && { echo "ERROR: VAULT_TOKEN no disponible"; exit 1; }

kubectl --kubeconfig="$KUBECONFIG" exec -n secrets vault-0 -- \
    sh -c "VAULT_TOKEN=${VAULT_TOKEN} vault kv put secret/${SECRET_PATH} "STORAGE_ENDPOINT=http://minio.infra.svc.cluster.local:9000" "STORAGE_ACCESS_KEY=minioadmin" "STORAGE_SECRET_KEY=changeme_minio" "REPORT_BUCKET=controlstock-reports" "KAFKA_BOOTSTRAP_SERVERS=kafka-kafka-bootstrap.messaging.svc.cluster.local:9092" "REPORTING_JDBC_URL=jdbc:postgresql://postgresql.data.svc.cluster.local:5432/controlstock_reporting" "REPORTING_JDBC_USER=controlstock_reporting_user" "REPORTING_JDBC_PASSWORD=changeme_controlstock_reporting" "MONGO_URI=mongodb://mongodb.data.svc.cluster.local:27017" "MONGO_READ_DB=readmodel" "MONGO_READ_COLLECTION=ventas""

echo "Secret creado/actualizado: secret/${SECRET_PATH}"
