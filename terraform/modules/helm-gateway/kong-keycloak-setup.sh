#!/usr/bin/env bash
# kong-keycloak-setup.sh — Configura Kong JWT plugin con la clave pública de Keycloak
set -euo pipefail
KUBECONFIG_PATH="$1"
KEYCLOAK_URL="${2:-http://keycloak.identity.svc.cluster.local:8080}"
KEYCLOAK_REALM="${3:-myproject}"

echo "[INFO] Esperando Kong Admin API..."
kubectl --kubeconfig="$KUBECONFIG_PATH" wait deploy/kong-kong \
  -n gateway --for=condition=Available --timeout=120s || true

# Port-forward Kong Admin API (ClusterIP — solo accesible dentro del cluster)
kubectl --kubeconfig="$KUBECONFIG_PATH" \
  port-forward -n gateway svc/kong-kong-admin 18001:8001 &>/dev/null &
PF_PID=$!
sleep 5

KONG_ADMIN="http://localhost:18001"

echo "[INFO] Obteniendo clave pública de Keycloak (realm: $KEYCLOAK_REALM)..."
PUBLIC_KEY=$(curl -sf "${KEYCLOAK_URL}/realms/${KEYCLOAK_REALM}" 2>/dev/null \
  | python3 -c "import sys,json; print(json.load(sys.stdin).get('public_key',''))" 2>/dev/null || true)

if [[ -n "$PUBLIC_KEY" ]]; then
  PEM="-----BEGIN PUBLIC KEY-----\n${PUBLIC_KEY}\n-----END PUBLIC KEY-----"

  # Consumer genérico para tokens Keycloak
  curl -sf -X PUT "${KONG_ADMIN}/consumers/keycloak-users" \
    -H "Content-Type: application/json" \
    -d '{"username":"keycloak-users"}' -o /dev/null 2>/dev/null || true

  # Registrar RSA public key como credencial JWT
  curl -sf -X POST "${KONG_ADMIN}/consumers/keycloak-users/jwt" \
    -H "Content-Type: application/json" \
    -d "{
      \"algorithm\": \"RS256\",
      \"key\":       \"${KEYCLOAK_URL}/realms/${KEYCLOAK_REALM}\",
      \"rsa_public_key\": \"${PEM}\"
    }" -o /dev/null 2>/dev/null \
    && echo "[OK] Clave pública Keycloak registrada en Kong (consumer: keycloak-users)" \
    || echo "[SKIP] Credencial JWT ya registrada"
else
  echo "[WARN] No se pudo obtener la clave pública de Keycloak — configura manualmente"
fi

# Plugin JWT global (valida tokens en todos los servicios registrados en Kong)
curl -sf -X POST "${KONG_ADMIN}/plugins" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "jwt",
    "config": {
      "key_claim_name":    "iss",
      "claims_to_verify":  ["exp"],
      "uri_param_names":   ["jwt"],
      "cookie_names":      []
    }
  }' -o /dev/null 2>/dev/null \
  && echo "[OK] Plugin JWT global habilitado en Kong" \
  || echo "[SKIP] Plugin JWT ya configurado"

# Plugin rate-limiting global (protección básica)
curl -sf -X POST "${KONG_ADMIN}/plugins" \
  -H "Content-Type: application/json" \
  -d '{"name":"rate-limiting","config":{"minute":200,"policy":"local"}}' \
  -o /dev/null 2>/dev/null \
  && echo "[OK] Plugin rate-limiting global habilitado" || true

# Plugin CORS global
curl -sf -X POST "${KONG_ADMIN}/plugins" \
  -H "Content-Type: application/json" \
  -d '{"name":"cors","config":{"origins":["*"],"methods":["GET","POST","PUT","PATCH","DELETE","OPTIONS"],"headers":["Authorization","Content-Type","Accept"],"exposed_headers":["X-Auth-Token"],"credentials":true,"max_age":3600}}' \
  -o /dev/null 2>/dev/null \
  && echo "[OK] Plugin CORS global habilitado" || true

kill $PF_PID 2>/dev/null || true
echo "[OK] Configuración Kong-Keycloak completada"
