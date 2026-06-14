resource "helm_release" "vault" {
  name       = "vault"
  repository = "https://helm.releases.hashicorp.com"
  chart      = "vault"
  version    = "0.28.0"
  namespace  = "secrets"
  wait       = true
  timeout    = 300
  values = [<<-YAML
    server:
      dev:
        enabled: false
      standalone:
        enabled: true
        config: |
          ui = true
          listener "tcp" {
            tls_disable     = 1
            address         = "[::]:8200"
            cluster_address = "[::]:8201"
          }
          storage "file" {
            path = "/vault/data"
          }
      dataStorage:
        enabled: true
        size: 2Gi
      service:
        type: NodePort
        nodePort: 8200
    ui:
      enabled: true
  YAML
  ]
}

# Inicializa Vault (genera vault-init.json con unseal key + root token)
resource "null_resource" "vault_init" {
  depends_on = [helm_release.vault]
  provisioner "local-exec" {
    command = <<-CMD
      echo "[INFO] Esperando Vault pod Ready..."
      kubectl --kubeconfig='${var.kubeconfig_path}' wait pod/vault-0 \
        -n secrets --for=condition=Ready --timeout=120s || true
      echo "[INFO] Inicializando Vault (idempotente)..."
      kubectl --kubeconfig='${var.kubeconfig_path}' exec -n secrets vault-0 -- \
        vault operator init -key-shares=1 -key-threshold=1 -format=json \
        > vault-init.json 2>/dev/null \
        && echo "[OK] vault-init.json generado — guardar en lugar seguro" \
        || echo "[SKIP] Vault ya inicializado"
    CMD
  }
  triggers = { vault_version = helm_release.vault.version }
}

# Unseal + habilitar KV v2 + política base de servicios + kubernetes auth
resource "null_resource" "vault_setup" {
  depends_on = [null_resource.vault_init]
  provisioner "local-exec" {
    command = "bash '${path.module}/vault-post-init.sh' '${var.kubeconfig_path}' vault-init.json"
  }
  triggers = { vault_init_id = null_resource.vault_init.id }
}
