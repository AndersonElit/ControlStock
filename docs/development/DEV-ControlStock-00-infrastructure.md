# Etapa 0 — Infraestructura VPS (K3s + Terraform + Helm)

---

## 1. Objetivo

Aprovisionar el ambiente de infraestructura base sobre el cual se desplegará el sistema ControlStock. Esta etapa instala y configura todos los servicios de plataforma que los microservicios de aplicación requieren para operar: base de datos relacional, base de datos documental, broker de mensajería, gestión de identidad, gestión de secretos, API Gateway, almacenamiento de objetos, herramientas CI/CD, pila de observabilidad y servicios de soporte (Narayana LRA para coordinación de sagas, WireMock para simulación de dependencias externas, OpenFaaS para funciones serverless).

Al finalizar esta etapa, el entorno VPS debe tener K3s ejecutándose con todos los namespaces, Helm releases y configuraciones post-instalación listos, de forma que cualquier microservicio pueda desplegarse inmediatamente sin necesidad de modificar la infraestructura base.

Esta etapa debe completarse **antes** de iniciar cualquier otra etapa del plan de desarrollo (bases de datos, scaffolding, microservicios o frontend).

---

## 2. Prerrequisitos

Los siguientes elementos deben estar disponibles en la máquina local del desarrollador antes de iniciar esta etapa:

### Herramientas en la máquina local

| Herramienta | Versión mínima | Verificación |
|---|---|---|
| Terraform | ≥ 1.7 | `terraform --version` |
| kubectl | ≥ 1.29 | `kubectl version --client` |
| Helm | ≥ 3.14 | `helm version` |
| Docker | ≥ 25 | `docker --version` |
| ssh / ssh-keygen | — | `ssh -V` |
| QEMU/KVM (solo local) | — | `virsh --version` |
| OCI CLI (solo prod) | — | `oci --version` |
| curl / jq | — | `curl --version && jq --version` |
| bash | ≥ 5 | `bash --version` |

### Accesos y credenciales

| Recurso | Local | Producción |
|---|---|---|
| Acceso SSH al VPS | Par de claves SSH (`~/.ssh/controlstock_local`) | Par de claves SSH (`~/.ssh/controlstock_prod`) |
| Configuración OCI | No requerida | `~/.oci/config` con API key OCI |
| Variables de entorno | `VPS_IP` exportada | `VPS_IP` exportada (IP pública OCI) |
| Repositorio del proyecto | Clonado localmente | Clonado localmente |

### Variables de entorno requeridas

Antes de ejecutar cualquier script, exportar las siguientes variables:

```bash
# IP del VPS (asignada por QEMU en local, IP pública en prod)
export VPS_IP=<VPS_IP>

# Nombre del proyecto (no modificar)
export PROJECT_NAME=controlstock

# Entorno objetivo: local | prod
export ENV=local
```

---

## 3. Paso 0: Provisionar el VPS (prerrequisito previo a la infraestructura)

Este paso crea la máquina virtual sobre la cual se instalará K3s. Ejecutar **solo uno** de los dos procedimientos según el entorno objetivo.

### Opción A — Entorno Local (QEMU/KVM)

El script `qemu-vps.sh` crea y arranca una VM Ubuntu 24.04 LTS con los recursos mínimos para ejecutar K3s con todos los componentes de ControlStock.

**Recursos recomendados para el VPS local:**

| Recurso | Mínimo | Recomendado |
|---|---|---|
| RAM | 8 GB | 16 GB |
| vCPUs | 4 | 8 |
| Disco | 60 GB | 100 GB |
| Red | Bridge/NAT | Bridge (acceso directo desde host) |

**Ejecutar:**

```bash
bash .claude/scripts/qemu-vps.sh \
  --name controlstock-local \
  --memory 8192 \
  --cpus 4 \
  --disk 60G \
  --os ubuntu-24.04 \
  --ssh-key ~/.ssh/controlstock_local.pub
```

**Salida esperada:**

```
[qemu-vps] VM 'controlstock-local' creada exitosamente.
[qemu-vps] IP asignada: 192.168.122.X
[qemu-vps] Acceso: ssh ubuntu@192.168.122.X -i ~/.ssh/controlstock_local
```

Exportar la IP asignada:

```bash
export VPS_IP=192.168.122.X   # reemplazar con la IP impresa por qemu-vps.sh
```

**Verificar conectividad SSH:**

```bash
ssh ubuntu@${VPS_IP} -i ~/.ssh/controlstock_local "uname -a && free -h && df -h /"
```

### Opción B — Entorno Producción (Oracle Cloud OCI)

En producción, el VPS se aprovisiona en Oracle Cloud OCI mediante Terraform. Se asume que las credenciales OCI están configuradas en `~/.oci/config`.

**Requisitos previos OCI:**

- Compartment ID disponible.
- VCN y subnet pública creadas (o delegadas al módulo Terraform OCI).
- Cuota de instancias VM.Standard.A1.Flex (Ampere ARM) disponible.

**Ejecutar:**

```bash
terraform -chdir=infra/oci init

terraform -chdir=infra/oci apply \
  -var="project=controlstock" \
  -var="env=prod" \
  -var="ssh_public_key=$(cat ~/.ssh/controlstock_prod.pub)" \
  -auto-approve
```

**Obtener la IP pública:**

```bash
export VPS_IP=$(terraform -chdir=infra/oci output -raw instance_public_ip)
echo "VPS Producción en: ${VPS_IP}"
```

**Verificar conectividad SSH:**

```bash
ssh ubuntu@${VPS_IP} -i ~/.ssh/controlstock_prod "uname -a && free -h && df -h /"
```

**Nota para producción:** Asegurarse de que las reglas de Security List (OCI) abran los puertos NodePort requeridos: 80, 443, 3000, 3001, 8000, 8080, 8081, 8082, 8200, 9000, 9001, 9090, 9999.

---

## 4. Paso 1: Ejecutar el script de infraestructura base

El script `base-infrastructure-builder.sh` es el punto de entrada único para aprovisionar toda la infraestructura de ControlStock sobre el VPS. Instala K3s, genera y aplica los módulos Terraform con todos los Helm charts, y ejecuta la configuración post-instalación.

### Comando para entorno local

```bash
bash .claude/scripts/base-infrastructure-builder.sh \
  --vm-ip <VPS_IP> \
  --project controlstock \
  --pg-prefix controlstock \
  --mongo-prefix controlstock \
  --env local
```

> **Importante:** No usar `--no-lra`. Las Sagas Saga-01 (Reposición de inventario) y Saga-02 (Ajuste aprobado) requieren el coordinador Narayana LRA para la gestión del ciclo de vida de las transacciones distribuidas. Omitir LRA impediría el funcionamiento de integration-service.

> **Importante:** No usar `--no-wiremock` en entorno `local`. WireMock es requerido para simular el proveedor externo en las pruebas de integración de Saga-01.

### Comando para entorno producción

```bash
bash .claude/scripts/base-infrastructure-builder.sh \
  --vm-ip <VPS_IP> \
  --project controlstock \
  --pg-prefix controlstock \
  --mongo-prefix controlstock \
  --env prod \
  --no-wiremock
```

> En producción se usa `--no-wiremock` porque el proveedor externo es real y WireMock no debe estar expuesto.

### Fases de ejecución del script

El script ejecuta 4 fases secuenciales. Cada fase imprime su progreso con timestamps en la salida estándar.

#### Fase 1 — Instalación de K3s en el VPS

```
[FASE 1] Instalando K3s en ${VPS_IP}...
```

Acciones realizadas:
- Copia de la clave pública SSH al VPS para autenticación sin contraseña.
- Conexión SSH al VPS y ejecución del script de instalación oficial de K3s (`curl -sfL https://get.k3s.io | sh -s - --write-kubeconfig-mode 644`).
- Espera a que el API Server de K3s esté disponible (`kubectl cluster-info`).
- Descarga del kubeconfig desde el VPS y almacenamiento en `~/.kube/config-controlstock-${ENV}`.
- Exportación de la variable `KUBECONFIG=~/.kube/config-controlstock-${ENV}` en `~/.bashrc` o `~/.zshrc` del usuario local.

Verificación al finalizar la fase:
```bash
kubectl get nodes --kubeconfig ~/.kube/config-controlstock-local
# Esperado: un nodo en estado Ready
```

#### Fase 2 — Inicialización Terraform

```
[FASE 2] Inicializando módulos Terraform...
```

Acciones realizadas:
- Generación del árbol de módulos Terraform bajo `infra/terraform/` con la estructura:
  ```
  infra/terraform/
  ├── main.tf
  ├── variables.tf
  ├── outputs.tf
  ├── terraform.tfvars         # valores para el entorno indicado (local/prod)
  └── modules/
      ├── namespaces/
      ├── helm-infra/
      ├── helm-data/
      ├── helm-identity/
      ├── helm-secrets/
      ├── helm-cicd/
      ├── helm-observability/
      └── helm-support/
  ```
- Ejecución de `terraform init` para descargar providers (`hashicorp/kubernetes`, `hashicorp/helm`).
- Ejecución de `terraform validate` para verificar sintaxis.
- Ejecución de `terraform plan` y almacenamiento del plan en `infra/terraform/tfplan.bin`.

#### Fase 3 — Aplicación Terraform + Helm (despliegue de charts)

```
[FASE 3] Aplicando infraestructura (Terraform apply)...
```

Acciones realizadas:
- Ejecución de `terraform apply -auto-approve -plan=infra/terraform/tfplan.bin`.
- Los módulos se aplican en el siguiente orden respetando dependencias:
  1. `modules/namespaces` — crea todos los namespaces Kubernetes.
  2. `modules/helm-infra` — Traefik (IngressController), cert-manager, Kong.
  3. `modules/helm-data` — PostgreSQL 16, MongoDB 7, Strimzi Operator + Kafka KRaft.
  4. `modules/helm-identity` — Keycloak 24.
  5. `modules/helm-secrets` — HashiCorp Vault.
  6. `modules/helm-cicd` — Gitea, Jenkins, ArgoCD.
  7. `modules/helm-observability` — kube-prometheus-stack, Loki, Promtail, Tempo.
  8. `modules/helm-support` — Narayana LRA, WireMock (si `--no-wiremock` no está activado), OpenFaaS Operator + kafka-connector.

Cada módulo espera a que los pods estén en estado `Running/Ready` antes de proceder al siguiente módulo.

#### Fase 4 — Configuración post-instalación

```
[FASE 4] Ejecutando configuración post-instalación...
```

Acciones realizadas en orden:

**4a — Inicialización de Vault:**
- Inicializa Vault (`vault operator init`).
- Almacena las unseal keys y el root token en `~/.config/controlstock/vault-init.json` (permisos 600).
- Realiza unseal de Vault con las 3 primeras unseal keys.
- Habilita el motor KV v2 en la ruta `secret/`.
- Crea la política `controlstock` que permite `read` en `secret/controlstock/*`.

**4b — Configuración de Keycloak:**
- Crea el realm `controlstock` con tiempo de sesión de 8 horas.
- Crea los clientes OIDC: `controlstock-frontend` (público, flujo Authorization Code + PKCE) y `controlstock-backend` (confidencial, flujo Client Credentials).
- Crea los roles de realm: `Operador`, `Supervisor`, `Admin`, `Gerente`, `Auditor`.
- Crea el usuario administrativo inicial: `admin@controlstock.local` / contraseña almacenada en Vault bajo `secret/controlstock/keycloak`.

**4c — Creación de topics Kafka:**
- Crea los 14 topics Kafka del proyecto con 3 particiones y factor de replicación 1 (local) o 3 (prod):
  ```
  controlstock.inventory.entradas
  controlstock.inventory.salidas
  controlstock.inventory.stock-actualizado
  controlstock.catalog.producto-creado
  controlstock.catalog.producto-actualizado
  controlstock.catalog.producto-inactivado
  controlstock.adjustment.ajuste-solicitado
  controlstock.adjustment.ajuste-aprobado
  controlstock.adjustment.ajuste-rechazado
  controlstock.supplier.proveedor-actualizado
  controlstock.integration.solicitud-reposicion-enviada
  controlstock.reporting.requests
  controlstock.reporting.parquet-generado
  controlstock.reporting.etl-fallido
  ```

**4d — Configuración de MinIO:**
- Crea el bucket `controlstock-reports` con política de acceso privado.
- Crea las credenciales de acceso programático y las almacena en Vault bajo `secret/controlstock/minio`.
- Crea la estructura de prefijos en el bucket: `parquet/`, `xlsx/`, `csv/`, `pdf/`.

**4e — Configuración de Gitea:**
- Crea la organización `controlstock` en Gitea.
- Crea los repositorios para cada microservicio:
  - `iam-service`, `catalog-service`, `inventory-service`, `adjustment-service`
  - `alert-service`, `supplier-service`, `report-service`, `audit-service`
  - `integration-service`, `report-etl-service`, `report-format-consumer`
  - `frontend-controlstock`, `helm-charts`, `gitops-manifests`
- Configura el Package Registry como imagen registry para el proyecto.

**4f — Configuración de ArgoCD:**
- Conecta ArgoCD al repositorio `gitops-manifests` de Gitea.
- Crea el AppProject `controlstock` con permisos sobre los namespaces `app`, `infra`, `openfaas`.

**4g — Configuración de Jenkins:**
- Importa las credenciales de Gitea, Vault y el kubeconfig en el almacén de credenciales de Jenkins.
- Crea las vistas de pipelines por etapa (infraestructura, servicios, frontend).

### Tabla de módulos Terraform

| Módulo | Helm chart / Recurso Kubernetes | Namespace | NodePort / Acceso externo |
|---|---|---|---|
| `modules/namespaces` | `kubernetes_namespace`: `data`, `messaging`, `identity`, `secrets`, `cicd`, `observability`, `infra`, `openfaas`, `app` | — | — |
| `modules/helm-infra` | Traefik `traefik/traefik`, cert-manager `jetstack/cert-manager`, Kong `kong/kong` | `infra` | Kong Proxy: `80` (HTTP), `443` (HTTPS), `8000` (HTTP sin TLS) |
| `modules/helm-data` | PostgreSQL 16 `bitnami/postgresql`, MongoDB 7 `bitnami/mongodb`, Strimzi Operator `strimzi/strimzi-kafka-operator` + `KafkaNodePool` KRaft | `data`, `messaging` | Interno (sin NodePort; usar `kubectl port-forward`) |
| `modules/helm-identity` | Keycloak 24 `bitnami/keycloak` | `identity` | NodePort `8082` |
| `modules/helm-secrets` | HashiCorp Vault `hashicorp/vault` (modo dev desactivado; modo standalone con storage file) | `secrets` | NodePort `8200` |
| `modules/helm-cicd` | Gitea `gitea-charts/gitea`, Jenkins `jenkinsci/jenkins`, ArgoCD `argo/argo-cd` | `cicd` | Gitea: `3000`, Jenkins: `8080`, ArgoCD: `8081` |
| `modules/helm-observability` | kube-prometheus-stack `prometheus-community/kube-prometheus-stack`, Loki `grafana/loki`, Promtail `grafana/promtail`, Tempo `grafana/tempo` | `observability` | Prometheus: `9090`, Grafana: `3001` |
| `modules/helm-support` | Narayana LRA `controlstock/narayana-lra` (chart propio), WireMock `wiremock/wiremock`, OpenFaaS `openfaas/openfaas`, kafka-connector (OpenFaaS) | `infra`, `openfaas` | Narayana LRA: `50000` (interno), WireMock: `9999`, OpenFaaS Gateway: `8085` (interno) |

### Tiempo estimado de ejecución

| Fase | Tiempo estimado |
|---|---|
| Fase 1 — K3s | 5–10 minutos |
| Fase 2 — Terraform init | 2–3 minutos |
| Fase 3 — Terraform apply | 15–25 minutos |
| Fase 4 — Post-instalación | 5–10 minutos |
| **Total** | **27–48 minutos** |

---

## 5. Paso 2: Verificar el ambiente

Una vez finalizado el script de infraestructura base, ejecutar el script de verificación para confirmar que todos los servicios están operativos:

```bash
bash .claude/scripts/init-dev-environment.sh \
  -P controlstock \
  --vm-ip <VPS_IP>
```

El script ejecuta las siguientes verificaciones:

1. **Conectividad K3s:** `kubectl get nodes` — el nodo debe estar en estado `Ready`.
2. **Pods en estado Running:** `kubectl get pods -A` — todos los pods de los namespaces `data`, `messaging`, `identity`, `secrets`, `cicd`, `observability`, `infra`, `openfaas` deben estar `Running` o `Completed`.
3. **Endpoints HTTP:** Realiza `curl -s` con timeout de 5 segundos a cada endpoint externo y verifica el código de respuesta HTTP esperado.
4. **Vault status:** Verifica que Vault esté inicializado y sellado correctamente (`vault status`).
5. **Kafka topics:** Lista los topics Kafka y verifica que los 14 topics del proyecto existan.
6. **Keycloak realm:** Verifica que el realm `controlstock` exista mediante la API REST de Keycloak.
7. **MinIO bucket:** Verifica que el bucket `controlstock-reports` exista.
8. **Gitea repositorios:** Verifica que los repositorios de la organización `controlstock` existan.

### Verificación manual de endpoints

| Servicio | Endpoint externo | Código HTTP esperado | Comando de verificación |
|---|---|---|---|
| Keycloak | `http://<VPS_IP>:8082` | 200 | `curl -s -o /dev/null -w "%{http_code}" http://<VPS_IP>:8082` |
| Keycloak OIDC | `http://<VPS_IP>:8082/realms/controlstock/.well-known/openid-configuration` | 200 | `curl -s http://<VPS_IP>:8082/realms/controlstock/.well-known/openid-configuration \| jq .issuer` |
| HashiCorp Vault | `http://<VPS_IP>:8200/v1/sys/health` | 200 / 501 | `curl -s http://<VPS_IP>:8200/v1/sys/health \| jq .initialized` |
| Gitea | `http://<VPS_IP>:3000` | 200 | `curl -s -o /dev/null -w "%{http_code}" http://<VPS_IP>:3000` |
| Jenkins | `http://<VPS_IP>:8080` | 200 / 403 | `curl -s -o /dev/null -w "%{http_code}" http://<VPS_IP>:8080` |
| ArgoCD | `http://<VPS_IP>:8081` | 200 | `curl -s -o /dev/null -w "%{http_code}" http://<VPS_IP>:8081` |
| Kong Proxy | `http://<VPS_IP>:8000` | 404 (sin rutas) | `curl -s -o /dev/null -w "%{http_code}" http://<VPS_IP>:8000` |
| Kong Admin | `http://<VPS_IP>:8001` | 200 | `curl -s http://<VPS_IP>:8001 \| jq .version` |
| MinIO API | `http://<VPS_IP>:9000/minio/health/live` | 200 | `curl -s -o /dev/null -w "%{http_code}" http://<VPS_IP>:9000/minio/health/live` |
| MinIO Console | `http://<VPS_IP>:9001` | 200 | `curl -s -o /dev/null -w "%{http_code}" http://<VPS_IP>:9001` |
| Prometheus | `http://<VPS_IP>:9090/-/ready` | 200 | `curl -s http://<VPS_IP>:9090/-/ready` |
| Grafana | `http://<VPS_IP>:3001/api/health` | 200 | `curl -s http://<VPS_IP>:3001/api/health \| jq .database` |
| WireMock | `http://<VPS_IP>:9999/__admin/health` | 200 | `curl -s http://<VPS_IP>:9999/__admin/health` |

### Verificación de servicios internos (via kubectl port-forward)

Para verificar los servicios que no tienen NodePort externo:

```bash
# PostgreSQL
kubectl port-forward -n data svc/postgresql 5432:5432 &
psql -h localhost -p 5432 -U postgres -c "SELECT version();"
pkill -f "port-forward.*5432"

# MongoDB
kubectl port-forward -n data svc/mongo 27017:27017 &
mongosh --host localhost --port 27017 --eval "db.runCommand({ping: 1})"
pkill -f "port-forward.*27017"

# Kafka (via Strimzi kafka-topics.sh)
kubectl port-forward -n messaging svc/kafka-kafka-bootstrap 9092:9092 &
kafka-topics.sh --bootstrap-server localhost:9092 --list
pkill -f "port-forward.*9092"

# Narayana LRA
kubectl port-forward -n infra svc/narayana-lra 50000:50000 &
curl -s http://localhost:50000/lra-coordinator/ | head -20
pkill -f "port-forward.*50000"
```

---

## 6. Paso 3: Variables de entorno base

Después de verificar el ambiente, configurar las variables de entorno base que serán utilizadas por todos los scripts y pipelines posteriores. Se recomienda añadirlas al archivo `~/.bashrc` o `~/.zshrc` y también al archivo `.env.local` del proyecto (este archivo NO debe commitearse a Git).

### Variables de entorno requeridas

| Variable | Valor (local) | Valor (prod) | Descripción |
|---|---|---|---|
| `VPS_IP` | `<VPS_IP>` (IP QEMU) | `<VPS_IP>` (IP pública OCI) | IP del VPS con K3s |
| `GITEA_REGISTRY` | `<VPS_IP>:3000/controlstock` | `<region>.ocir.io/controlstock` | Registro de imágenes Docker |
| `KUBECONFIG` | `~/.kube/config-controlstock-local` | `~/.kube/config-controlstock-prod` | Configuración kubectl |
| `VAULT_ADDR` | `http://<VPS_IP>:8200` | `http://<VPS_IP>:8200` | Dirección del servidor Vault |
| `VAULT_TOKEN` | (leído de `vault-init.json`) | (leído de `vault-init.json`) | Token raíz de Vault (solo para setup inicial) |
| `KEYCLOAK_URL` | `http://<VPS_IP>:8082` | `http://<VPS_IP>:8082` | URL base de Keycloak |
| `KONG_PROXY_URL` | `http://<VPS_IP>:8000` | `http://<VPS_IP>:8000` | URL del proxy Kong |
| `MINIO_ENDPOINT` | `http://<VPS_IP>:9000` | `http://<VPS_IP>:9000` | Endpoint MinIO API |
| `PROJECT_NAME` | `controlstock` | `controlstock` | Nombre del proyecto |
| `ENV` | `local` | `prod` | Entorno activo |

### Configuración en .bashrc / .zshrc

```bash
# ControlStock — Variables de infraestructura
export VPS_IP=<VPS_IP>
export GITEA_REGISTRY="${VPS_IP}:3000/controlstock"
export KUBECONFIG="${HOME}/.kube/config-controlstock-local"
export VAULT_ADDR="http://${VPS_IP}:8200"
export KEYCLOAK_URL="http://${VPS_IP}:8082"
export KONG_PROXY_URL="http://${VPS_IP}:8000"
export MINIO_ENDPOINT="http://${VPS_IP}:9000"
export PROJECT_NAME="controlstock"
export ENV="local"
```

Recargar la sesión de shell:

```bash
source ~/.bashrc   # o source ~/.zshrc
```

### Obtención del root token de Vault

El root token de Vault se almacena durante la Fase 4 de la instalación en el archivo:

```
~/.config/controlstock/vault-init.json
```

El archivo tiene la siguiente estructura:

```json
{
  "unseal_keys_b64": [
    "UNSEAL_KEY_1_BASE64",
    "UNSEAL_KEY_2_BASE64",
    "UNSEAL_KEY_3_BASE64",
    "UNSEAL_KEY_4_BASE64",
    "UNSEAL_KEY_5_BASE64"
  ],
  "unseal_keys_hex": [
    "UNSEAL_KEY_1_HEX",
    "UNSEAL_KEY_2_HEX",
    "UNSEAL_KEY_3_HEX",
    "UNSEAL_KEY_4_HEX",
    "UNSEAL_KEY_5_HEX"
  ],
  "unseal_threshold": 3,
  "unseal_shares": 5,
  "root_token": "hvs.XXXXXXXXXXXXXXXXXXXX"
}
```

> **Seguridad:** El archivo `vault-init.json` contiene las unseal keys y el root token. Este archivo tiene permisos `600` (solo lectura/escritura para el propietario). **Nunca** debe commitearse a Git ni compartirse. En ambientes de equipo, almacenar el root token en un gestor de contraseñas seguro (1Password, Bitwarden corporativo) y eliminar el archivo local después de extraer las credenciales.

Para extraer el root token y exportarlo:

```bash
export VAULT_TOKEN=$(jq -r '.root_token' ~/.config/controlstock/vault-init.json)

# Verificar acceso a Vault
vault status
vault kv list secret/controlstock/
```

### Re-unseal de Vault tras reinicio del VPS

Vault se sella automáticamente cuando el pod se reinicia. Para hacer unseal:

```bash
# Leer las unseal keys del archivo
UNSEAL_KEY_1=$(jq -r '.unseal_keys_b64[0]' ~/.config/controlstock/vault-init.json)
UNSEAL_KEY_2=$(jq -r '.unseal_keys_b64[1]' ~/.config/controlstock/vault-init.json)
UNSEAL_KEY_3=$(jq -r '.unseal_keys_b64[2]' ~/.config/controlstock/vault-init.json)

# Hacer unseal (requiere 3 de 5 keys)
vault operator unseal "${UNSEAL_KEY_1}"
vault operator unseal "${UNSEAL_KEY_2}"
vault operator unseal "${UNSEAL_KEY_3}"

# Verificar estado
vault status
# sealed: false
```

Alternativamente, para automatizar el unseal en entornos de desarrollo (no producción), el script de conveniencia:

```bash
bash .claude/scripts/vault-unseal.sh --vault-init ~/.config/controlstock/vault-init.json
```

### Almacenamiento de secretos base en Vault

Una vez que Vault está disponible, almacenar los secretos base de infraestructura. Estos secretos serán leídos por los microservicios mediante el Vault Agent Injector o las variables de entorno configuradas en el Helm chart de cada servicio.

```bash
# Exportar VAULT_TOKEN antes de ejecutar estos comandos
export VAULT_TOKEN=$(jq -r '.root_token' ~/.config/controlstock/vault-init.json)

# PostgreSQL (contraseña del superusuario - obtenida de la instalación del chart)
vault kv put secret/controlstock/postgresql \
  host="postgresql.data.svc.cluster.local" \
  port="5432" \
  username="postgres" \
  password="$(kubectl get secret -n data postgresql -o jsonpath='{.data.postgres-password}' | base64 -d)"

# MongoDB
vault kv put secret/controlstock/mongodb \
  host="mongo.data.svc.cluster.local" \
  port="27017" \
  username="root" \
  password="$(kubectl get secret -n data mongo-mongodb -o jsonpath='{.data.mongodb-root-password}' | base64 -d)"

# Kafka (sin autenticación en local; con SASL en prod)
vault kv put secret/controlstock/kafka \
  bootstrap_servers="kafka-kafka-bootstrap.messaging.svc.cluster.local:9092" \
  security_protocol="PLAINTEXT"

# Keycloak admin
vault kv put secret/controlstock/keycloak \
  url="http://keycloak.identity.svc.cluster.local:8080" \
  realm="controlstock" \
  admin_user="admin" \
  admin_password="$(kubectl get secret -n identity keycloak -o jsonpath='{.data.admin-password}' | base64 -d)" \
  client_id="controlstock-backend" \
  client_secret="$(kubectl get secret -n identity keycloak-clients -o jsonpath='{.data.backend-client-secret}' | base64 -d 2>/dev/null || echo 'pendiente-de-crear')"

# MinIO
vault kv put secret/controlstock/minio \
  endpoint="http://minio.data.svc.cluster.local:9000" \
  bucket="controlstock-reports" \
  access_key="$(kubectl get secret -n data minio -o jsonpath='{.data.root-user}' | base64 -d)" \
  secret_key="$(kubectl get secret -n data minio -o jsonpath='{.data.root-password}' | base64 -d)"

# Verificar que los secretos están almacenados
vault kv list secret/controlstock/
```

---

## 7. Criterios de Aceptación

Los siguientes criterios deben cumplirse para dar por completada la Etapa 0. La verificación puede realizarse manual o automáticamente mediante el script `init-dev-environment.sh`.

### Infraestructura K3s

- [ ] El comando `kubectl get nodes` muestra el nodo del VPS en estado `Ready`.
- [ ] El comando `kubectl get pods -A` no muestra pods en estado `CrashLoopBackOff`, `Error` ni `Pending` por más de 5 minutos.
- [ ] Todos los namespaces requeridos existen: `data`, `messaging`, `identity`, `secrets`, `cicd`, `observability`, `infra`, `openfaas`, `app`.
- [ ] El archivo `~/.kube/config-controlstock-local` (o `prod`) existe y la variable `KUBECONFIG` apunta a él.

### Base de datos

- [ ] PostgreSQL 16 responde a conexiones en `postgresql.data.svc.cluster.local:5432` con el usuario `postgres` y la contraseña almacenada en Vault.
- [ ] MongoDB 7 responde a conexiones en `mongo.data.svc.cluster.local:27017` con el usuario `root` y la contraseña almacenada en Vault.
- [ ] No existen bases de datos de aplicación aún (se crearán en Etapa 1); solo la base `postgres` y `admin` deben existir.

### Kafka

- [ ] El Strimzi Operator está en estado `Running`.
- [ ] El `KafkaNodePool` está en estado `Ready` y Kafka KRaft opera sin ZooKeeper.
- [ ] Los 14 topics Kafka del proyecto están creados y visibles mediante `kafka-topics.sh --list`.
- [ ] El bootstrap server `kafka-kafka-bootstrap.messaging.svc.cluster.local:9092` acepta conexiones de productores y consumidores de prueba.

### Identity y Secretos

- [ ] Keycloak 24 responde en `http://<VPS_IP>:8082` con código HTTP 200.
- [ ] El realm `controlstock` existe en Keycloak.
- [ ] Los clientes OIDC `controlstock-frontend` y `controlstock-backend` están creados.
- [ ] Los roles `Operador`, `Supervisor`, `Admin`, `Gerente`, `Auditor` existen en el realm.
- [ ] El usuario `admin@controlstock.local` puede autenticarse en Keycloak.
- [ ] HashiCorp Vault responde en `http://<VPS_IP>:8200/v1/sys/health` con `initialized: true` y `sealed: false`.
- [ ] El motor KV v2 está habilitado en `secret/`.
- [ ] Los secretos base (`postgresql`, `mongodb`, `kafka`, `keycloak`, `minio`) existen en `secret/controlstock/`.
- [ ] El archivo `~/.config/controlstock/vault-init.json` existe con permisos `600`.

### API Gateway

- [ ] Kong 3.x responde en `http://<VPS_IP>:8000` (proxy) y `http://<VPS_IP>:8001` (admin API).
- [ ] El comando `curl -s http://<VPS_IP>:8001 | jq .version` devuelve la versión 3.x de Kong.
- [ ] No hay rutas configuradas aún (se configurarán en las etapas de microservicios).

### Almacenamiento de objetos

- [ ] MinIO responde en `http://<VPS_IP>:9000/minio/health/live` con código HTTP 200.
- [ ] El bucket `controlstock-reports` existe con los prefijos `parquet/`, `xlsx/`, `csv/`, `pdf/`.
- [ ] La consola MinIO es accesible en `http://<VPS_IP>:9001`.

### CI/CD

- [ ] Gitea responde en `http://<VPS_IP>:3000` con código HTTP 200.
- [ ] La organización `controlstock` existe en Gitea con los repositorios listados en el Paso 1 Fase 4e.
- [ ] El Package Registry de Gitea acepta `docker login <VPS_IP>:3000` con credenciales válidas.
- [ ] Jenkins responde en `http://<VPS_IP>:8080` y el panel principal es accesible.
- [ ] ArgoCD responde en `http://<VPS_IP>:8081` y el AppProject `controlstock` está configurado.
- [ ] ArgoCD tiene conexión al repositorio `gitops-manifests` de Gitea (estado `ConnectionSucceeded`).

### Observabilidad

- [ ] Prometheus responde en `http://<VPS_IP>:9090/-/ready` con código HTTP 200.
- [ ] La página `http://<VPS_IP>:9090/targets` muestra targets de kube-state-metrics y node-exporter en estado `UP`.
- [ ] Grafana responde en `http://<VPS_IP>:3001/api/health` con `database: ok`.
- [ ] Loki está configurado como fuente de datos en Grafana.
- [ ] Tempo está configurado como fuente de datos en Grafana.

### Servicios de soporte

- [ ] Narayana LRA responde en `narayana-lra.infra.svc.cluster.local:50000` (verificar via `kubectl port-forward`).
- [ ] WireMock responde en `http://<VPS_IP>:9999/__admin/health` con código HTTP 200 (solo en entorno `local`).
- [ ] OpenFaaS Operator está en estado `Running` en el namespace `openfaas`.
- [ ] La API de OpenFaaS Gateway está disponible en el namespace `openfaas`.

### Variables de entorno

- [ ] Las variables `VPS_IP`, `GITEA_REGISTRY`, `KUBECONFIG`, `VAULT_ADDR`, `KEYCLOAK_URL`, `KONG_PROXY_URL`, `MINIO_ENDPOINT`, `PROJECT_NAME`, `ENV` están configuradas en la sesión de shell del desarrollador.
- [ ] `vault status` retorna `Initialized: true` y `Sealed: false` usando las variables de entorno configuradas.
- [ ] `kubectl cluster-info` retorna la URL del API server del clúster usando `KUBECONFIG` configurado.

---

*Generado: 2026-06-13 | Proyecto: ControlStock | Etapa SDLC: Implementación — Etapa 0 (Infraestructura)*
