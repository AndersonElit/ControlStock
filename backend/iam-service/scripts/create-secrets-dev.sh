#!/usr/bin/env bash
# Crea/actualiza el secret de este servicio en HashiCorp Vault (K3s).
# Uso: KUBECONFIG=~/.kube/config-controlstock-local bash create-secrets-dev.sh
# Requiere que Vault esté unsealed y que vault-init.json esté disponible.

set -euo pipefail
KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config-controlstock-local}"
SECRET_PATH="controlstock/dev/iam-service"
INIT_FILE="${VAULT_INIT_FILE:-./vault-init.json}"

if [[ -f "$INIT_FILE" ]]; then
    VAULT_TOKEN=$(python3 -c "import json; print(json.load(open('$INIT_FILE'))['root_token'])" 2>/dev/null \
        || jq -r '.root_token' "$INIT_FILE" 2>/dev/null)
fi
VAULT_TOKEN="${VAULT_TOKEN:-${VAULT_ROOT_TOKEN:-}}"
[[ -z "$VAULT_TOKEN" ]] && { echo "ERROR: VAULT_TOKEN no disponible"; exit 1; }

kubectl --kubeconfig="$KUBECONFIG" exec -n secrets vault-0 -- \
    sh -c "VAULT_TOKEN=${VAULT_TOKEN} vault kv put secret/${SECRET_PATH} "SERVER_PORT=8081" "DB_URL=jdbc:postgresql://postgresql.data.svc.cluster.local:5432/controlstock_iam_service" "DB_REACTIVE_URL=r2dbc:postgresql://postgresql.data.svc.cluster.local:5432/controlstock_iam_service" "DB_USERNAME=controlstock_iam_service_user" "DB_PASSWORD=changeme_iam_service" "KEYCLOAK_URL=http://keycloak.identity.svc.cluster.local:8080" "KEYCLOAK_REALM=controlstock" "KEYCLOAK_CLIENT_ID=iam-service" "KEYCLOAK_CLIENT_SECRET=changeme_iam_service_client""

echo "Secret creado/actualizado: secret/${SECRET_PATH}"
