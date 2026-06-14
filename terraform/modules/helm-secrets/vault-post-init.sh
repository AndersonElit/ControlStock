#!/usr/bin/env bash
# vault-post-init.sh — Unseal Vault, habilita KV v2, crea política base de servicios
# Ejecutado por Terraform null_resource después de vault_init
set -euo pipefail
KUBECONFIG_PATH="$1"
INIT_FILE="${2:-vault-init.json}"

if [[ ! -f "$INIT_FILE" ]]; then
  echo "[SKIP] $INIT_FILE no encontrado — Vault ya configurado o unseal manual requerido"
  exit 0
fi

UNSEAL_KEY=$(python3 -c "import json; print(json.load(open('$INIT_FILE'))['unseal_keys_b64'][0])" 2>/dev/null \
  || jq -r '.unseal_keys_b64[0]' "$INIT_FILE" 2>/dev/null || true)
ROOT_TOKEN=$(python3 -c "import json; print(json.load(open('$INIT_FILE'))['root_token'])" 2>/dev/null \
  || jq -r '.root_token' "$INIT_FILE" 2>/dev/null || true)

[[ -z "$UNSEAL_KEY" || -z "$ROOT_TOKEN" ]] && { echo "[SKIP] Claves no legibles"; exit 0; }

echo "[INFO] Unsealing Vault..."
kubectl --kubeconfig="$KUBECONFIG_PATH" exec -n secrets vault-0 -- \
  vault operator unseal "$UNSEAL_KEY" 2>/dev/null || echo "[INFO] Ya estaba unsealed"

echo "[INFO] Habilitando KV v2 en secret/..."
kubectl --kubeconfig="$KUBECONFIG_PATH" exec -n secrets vault-0 -- \
  sh -c "VAULT_TOKEN=$ROOT_TOKEN vault secrets enable -path=secret kv-v2 2>/dev/null \
    || echo '[SKIP] KV v2 ya habilitado'"

echo "[INFO] Creando política services-read..."
printf 'path "secret/data/*/*" { capabilities = ["read"] }\npath "secret/metadata/*/*" { capabilities = ["list","read"] }\n' \
  | kubectl --kubeconfig="$KUBECONFIG_PATH" exec -i -n secrets vault-0 -- \
    sh -c "VAULT_TOKEN=$ROOT_TOKEN vault policy write services-read -"

echo "[INFO] Habilitando auth method kubernetes..."
kubectl --kubeconfig="$KUBECONFIG_PATH" exec -n secrets vault-0 -- \
  sh -c "VAULT_TOKEN=$ROOT_TOKEN vault auth enable kubernetes 2>/dev/null \
    || echo '[SKIP] kubernetes auth ya habilitado'"

echo "[OK] Vault: unsealed + KV v2 secret/ + policy services-read + kubernetes auth"
