# Etapa 2b — Configuración del Pipeline CI/CD

## Tabla de Contenidos

1. [Introducción](#introducción)
2. [Prerrequisitos](#prerrequisitos)
3. [Sección 0 — Ejecución Automatizada (Recomendado)](#sección-0--ejecución-automatizada-recomendado)
4. [Paso 1 — Generar la Shared Library](#paso-1--generar-la-shared-library)
5. [Paso 2 — Construir y Publicar Imagen del Controller](#paso-2--construir-y-publicar-imagen-del-controller)
6. [Paso 3 — Bootstrap del Cluster (Namespace + ServiceAccount)](#paso-3--bootstrap-del-cluster-namespace--serviceaccount)
7. [Paso 4 — Proveer Variables de Entorno y Credenciales al Controller (JCasC)](#paso-4--proveer-variables-de-entorno-y-credenciales-al-controller-jcasc)
8. [Paso 5 — Crear los Jobs de Pipeline en Jenkins y los Webhooks de Gitea](#paso-5--crear-los-jobs-de-pipeline-en-jenkins-y-los-webhooks-de-gitea)
9. [Paso 6 — Bootstrap de ArgoCD (ApplicationSet por Servicio)](#paso-6--bootstrap-de-argocd-applicationset-por-servicio)
10. [Paso 6b — Pipeline de Migraciones de Base de Datos (Liquibase)](#paso-6b--pipeline-de-migraciones-de-base-de-datos-liquibase)
11. [Verificación del Pipeline Completo](#verificación-del-pipeline-completo)
12. [Criterios de Aceptación](#criterios-de-aceptación)

---

## Introducción

Esta etapa configura el pipeline CI/CD **antes** de cualquier implementación de microservicio (inmediatamente después del scaffolding de la Etapa 2). La filosofía central es: **cada commit en cualquier rama es validado automáticamente**, garantizando que el código nunca llega a un ambiente sin haber pasado por compilación, pruebas de integración, análisis de calidad, escaneos de seguridad y verificación de imagen.

El modelo de entrega adoptado es **Jenkins CI → bumpImageTag → ArgoCD CD**:

- **Jenkins** actúa como motor de integración continua: compila, prueba, analiza, construye y publica la imagen Docker, y finalmente actualiza el tag de imagen en el repositorio de Helm charts.
- **ArgoCD** detecta el cambio en el repositorio de Helm charts y despliega la nueva versión al cluster K3s de forma automática (ambientes `local`/`dev`) o bajo aprobación manual (`prod`).

### Diagrama del Flujo CI/CD

```
git push (dev branch)
       │
       ▼
  [Gitea webhook]
       │
       ▼
  [Jenkins Multibranch Pipeline]
       │
  ┌────┴────────────────────────────────────────────┐
  │ computeImageTag → buildBackendService           │
  │ → runIntegrationTests → runQualityGates         │
  │ → runSecurityScans → buildAndPushImage          │
  │ → scanImage → bumpImageTag                      │
  │ → runSmokeTests → notify                        │
  └────────────────────────────────────────────────┘
       │
       ▼ (git push to controlstock-helm-charts)
  [ArgoCD Git Generator]
       │
       ▼
  [K3s VPS — Namespace apps]
  (local: auto-sync; prod: manual sync)
```

> **Migraciones de BD (carril paralelo).** Los cambios de esquema viven en el repo `controlstock-migrations` y los aplica un pipeline propio (Liquibase) **antes** del rollout — ver [Paso 6b](#paso-6b--pipeline-de-migraciones-de-base-de-datos-liquibase). No forman parte del build del servicio.

### Justificación de la configuración anticipada

Configurar CI/CD antes de la implementación de microservicios aporta los siguientes beneficios:

| Beneficio | Descripción |
|-----------|-------------|
| **Feedback inmediato** | El primer commit de código ya pasa por el pipeline completo |
| **Evitar deuda técnica** | No se acumulan commits sin validar para "configurar CI después" |
| **Infraestructura como código** | El pipeline mismo queda versionado y reproducible |
| **Integración temprana con K3s** | Los pods de agente Jenkins se validan con el cluster real desde el día 1 |
| **Detección temprana de vulnerabilidades** | OWASP + Trivy activos desde el primer artefacto |

---

## Prerrequisitos

Antes de ejecutar esta etapa, las siguientes etapas deben estar **completas y verificadas**:

| Etapa | Documento | Estado requerido |
|-------|-----------|-----------------|
| Etapa 0 — Infraestructura base | `DEV-ControlStock-00-infrastructure.md` | Completa |
| Etapa 0c — Observabilidad | `DEV-ControlStock-0c-observability.md` | Completa |
| Etapa 1 — Bases de datos | `DEV-ControlStock-01-databases.md` | Completa |
| Etapa 2 — Scaffold | `DEV-ControlStock-02-scaffold.md` | Completa (Jenkinsfile + Dockerfile + Helm charts generados) |

### Componentes de infraestructura requeridos

- **Jenkins Controller**: instalado como pod K3s en el namespace `cicd` por el script `base-infrastructure-builder.sh`. Accesible en `http://<VPS_IP>:8080`.
- **ArgoCD**: instalado en K3s (namespace `argocd`). Accesible vía `kubectl port-forward` o ingress configurado.
- **Gitea**: corriendo en K3s. Organización `controlstock` creada. Registry HTTP en `<VPS_IP>:3000`.
- **SonarQube**: pod K3s en namespace `cicd`. Token de acceso disponible.
- **HashiCorp Vault**: pod K3s en namespace `secrets`. Inicializado (vault-init.json disponible).
- **Keycloak**: pod K3s en namespace `auth`. Realm `controlstock` configurado.
- **Todos los repositorios de microservicios** generados en Gitea (desde Etapa 2).

### Verificación de prerrequisitos

```bash
# Verificar pods en namespace cicd
kubectl get pods -n cicd

# Salida esperada:
# jenkins-xxx      Running
# sonarqube-xxx    Running

# Verificar ArgoCD
kubectl get pods -n argocd

# Verificar Gitea accesible
curl -s http://<VPS_IP>:3000/api/v1/version | jq '.version'

# Verificar repositorios scaffold generados
curl -s -u gitea-admin:gitea-admin \
  http://<VPS_IP>:3000/api/v1/orgs/controlstock/repos | jq '.[].name'
```

---

## Sección 0 — Ejecución Automatizada (Recomendado)

Para el ambiente **local/dev**, la configuración completa del pipeline CI/CD puede ejecutarse de forma **totalmente autónoma** mediante un único comando:

```bash
bash .claude/scripts/setup-cicd-pipeline.sh \
  -P controlstock \
  -S "iam-service,catalog-service,inventory-service,adjustment-service,alert-service,supplier-service,report-service,audit-service,integration-service,report-etl-service" \
  --vps-ip <VPS_IP> \
  -F controlstock-web
```

### Parámetros del script

| Parámetro | Valor | Descripción |
|-----------|-------|-------------|
| `-P` | `controlstock` | Nombre del proyecto / organización Gitea |
| `-S` | `"iam-service,..."` | Lista de microservicios backend separados por coma |
| `--vps-ip` | `<VPS_IP>` | IP del VPS donde corre K3s |
| `-F` | `controlstock-web` | Nombre del frontend (se trata con `podFrontend.yaml`) |

### Secciones que ejecuta el script

El script ejecuta las siguientes secciones en orden secuencial:

```
Sección 0 → Generar Shared Library (jenkins-shared-library-builder.sh)
     │
     ▼
Sección 1 → Construir imagen controlstock-jenkins:latest → Push a Gitea registry
     │
     ▼
Sección 2 → Bootstrap K3s cluster (namespace jenkins + RBAC)
     │
     ▼
Sección 3 → JCasC → Reiniciar Jenkins pod → Verificar pod Running en K3s
     │       (Auto-completa: SONAR_URL/TOKEN, GITOPS_CREDENTIALS, VAULT_TOKEN)
     ▼
Sección 4 → Crear jobs Multibranch en Jenkins + Webhooks en Gitea
     │       (incluye el job `controlstock-migrations` — webhook solo push, Paso 6b)
     ▼
Sección 5 → Bootstrap ArgoCD (ApplicationSet + ApplicationProject)
     │
     ▼
Sección 6 → Verificación integral del pipeline
```

> **Nota — migración inicial.** El pipeline `controlstock-migrations` aplica los cambios de esquema **subsiguientes**. La carga inicial del esquema (primera vez) se hace fuera de banda con `.claude/scripts/run-liquibase-migrations.sh` (ver [Paso 6b](#paso-6b--pipeline-de-migraciones-de-base-de-datos-liquibase)); el script de CI/CD no la incluye porque depende de que las BDs (Etapa 1) ya existan.

### Auto-completado en ambiente local

En ambiente local, el script **rellena automáticamente** las siguientes variables sin intervención manual:

| Variable | Fuente de auto-completado |
|----------|--------------------------|
| `SONAR_URL` | Endpoint del pod SonarQube en K3s (`cicd` namespace) |
| `SONAR_TOKEN` | Token generado desde la API de SonarQube pod |
| `GITOPS_GIT_USERNAME` | Valor fijo: `gitea-admin` |
| `GITOPS_GIT_TOKEN` | Valor fijo: `gitea-admin` |
| `VAULT_TOKEN` | Leído de `vault-init.json` (generado en Etapa 0) |
| `SLACK_TEAM` | Vacío por defecto; el step `notify` usa log fallback |

> **Nota para producción:** En un ambiente de producción, estas variables deben configurarse manualmente con valores reales antes de ejecutar el script, o inyectarse vía variables de entorno de CI.

---

## Paso 1 — Generar la Shared Library

La Jenkins Shared Library centraliza la lógica reutilizable del pipeline. En lugar de duplicar código en los `Jenkinsfile` de cada microservicio, cada step reutilizable se define una sola vez en esta librería.

### Comando de generación

```bash
bash .claude/scripts/jenkins-shared-library-builder.sh \
  -P controlstock \
  -o jenkins-shared-library
```

El script crea el directorio `jenkins-shared-library/` localmente y luego crea el repositorio `controlstock/jenkins-shared-library` en Gitea y hace push automático a la rama `main`.

### Estructura de directorios

```
jenkins-shared-library/
├── vars/
│   ├── computeImageTag.groovy
│   ├── buildBackendService.groovy        # Maven: mvn clean package
│   ├── buildScalaBatchJob.groovy         # sbt clean test + sbt assembly
│   ├── runIntegrationTests.groovy        # mvn test -Pintegration
│   ├── runQualityGates.groovy            # SonarQube quality gate (maven/sbt)
│   ├── runSecurityScans.groovy           # OWASP Dependency Check + gitleaks
│   ├── buildAndPushImage.groovy          # Kaniko → Gitea/OCIR
│   ├── scanImage.groovy                  # Trivy CVE scan
│   ├── bumpImageTag.groovy               # update helm/<svc>/values-<env>.yaml
│   ├── runSmokeTests.groovy              # /actuator/health/readiness + /actuator/prometheus
│   ├── runDatabaseMigration.groovy       # Liquibase update in-cluster (repo controlstock-migrations)
│   └── notify.groovy                     # Slack (opcional en local, log fallback)
├── src/org/controlstock/
│   └── PipelineDefaults.groovy
├── resources/org/controlstock/
│   ├── podBackend.yaml                   # maven container + kaniko sidecar
│   ├── podFrontend.yaml                  # node container
│   ├── podScalaBatch.yaml                # sbt container (sin dind)
│   └── podMigrations.yaml                # liquibase container (migraciones de BD)
├── bootstrap/
│   └── jenkins-agent-rbac.yaml
└── docker/
    ├── Dockerfile                         # Imagen del controller Jenkins
    ├── plugins.txt                        # Lista de plugins Jenkins
    └── jenkins.yaml                       # Configuración JCasC
```

### Tabla de steps (vars/)

| Archivo | Stage del Pipeline | Descripción |
|---------|-------------------|-------------|
| `computeImageTag.groovy` | `Compute Tag` | Calcula el tag de imagen usando `GIT_COMMIT[0..7]` + timestamp. Para ramas `main`/`master` usa `release-<tag>`. Para `dev` usa `dev-<hash>`. |
| `buildBackendService.groovy` | `Build` | Compila el servicio Spring Boot con `mvn clean package -DskipTests`. Ejecuta en container `maven:3.9-eclipse-temurin-21`. |
| `buildScalaBatchJob.groovy` | `Build` | Compila el batch job Scala con `sbt clean test` seguido de `sbt assembly`. Ejecuta en container `sbtscala/scala-sbt`. |
| `runIntegrationTests.groovy` | `Integration Tests` | Ejecuta pruebas de integración con `mvn test -Pintegration`. Requiere Testcontainers habilitado en el pod. |
| `runQualityGates.groovy` | `Quality Gates` | Ejecuta análisis SonarQube (`mvn sonar:sonar` o `sbt sonar`). Bloquea el pipeline si el Quality Gate falla. Acepta parámetro `projectType: 'sbt'`. |
| `runSecurityScans.groovy` | `Security Scans` | Ejecuta OWASP Dependency-Check (`mvn dependency-check:check`) y gitleaks (detección de secretos en el historial). Acepta `projectType: 'sbt'`. |
| `buildAndPushImage.groovy` | `Build & Push Image` | Construye la imagen Docker con Kaniko (sin Docker daemon) y hace push al registry Gitea `<VPS_IP>:3000/controlstock`. |
| `scanImage.groovy` | `Scan Image` | Escanea la imagen publicada con Trivy buscando CVEs críticos y altos. Falla si encuentra CRITICAL. |
| `bumpImageTag.groovy` | `Bump Image Tag` | Actualiza `helm/<service>/values-<env>.yaml` en el repositorio `controlstock-helm-charts` en Gitea con el nuevo tag de imagen. Hace commit y push. |
| `runSmokeTests.groovy` | `Smoke Tests` | Verifica que el pod desplegado responde en `/actuator/health/readiness` y `/actuator/prometheus`. En local usa `SMOKE_USE_INCLUSTER=true`. |
| `runDatabaseMigration.groovy` | `DB Migration` | Aplica los changelogs Liquibase de un servicio como `update` desde un container `liquibase` in-cluster, con `--searchPath` + `--changeLogFile=root.yaml` relativo. Lo usa el pipeline del repo `controlstock-migrations` (Paso 6b). Acepta `dbName` override (p.ej. `report-service`→`controlstock_reporting`). |
| `notify.groovy` | `Notify` | Envía notificación al canal Slack configurado. **Si `SLACK_TEAM` está vacío (caso dev), registra el resultado en log y NO falla el build.** |

### Comportamiento del step `notify` en local

```groovy
// vars/notify.groovy
def call(Map config = [:]) {
    def slackTeam = env.SLACK_TEAM ?: ''
    if (slackTeam.isEmpty()) {
        echo "[NOTIFY] SLACK_TEAM no configurado — resultado: ${config.status ?: 'SUCCESS'}"
        echo "[NOTIFY] Pipeline: ${env.JOB_NAME} #${env.BUILD_NUMBER}"
        return  // NO falla el build
    }
    // ... envío real a Slack
}
```

### Lista de plugins del controller (plugins.txt)

```
workflow-aggregator:latest
git:latest
multibranch-scan-webhook-trigger:latest
blueocean:latest
sonar:latest
dependency-check-jenkins-plugin:latest
kubernetes:latest
pipeline-stage-view:latest
credentials-binding:latest
vault-plugin:latest
configuration-as-code:latest
job-dsl:latest
pipeline-utility-steps:latest
timestamper:latest
ansicolor:latest
build-timeout:latest
ws-cleanup:latest
junit:latest
jacoco:latest
```

### URL del repositorio Shared Library

```
http://<VPS_IP>:3000/controlstock/jenkins-shared-library.git
```

Esta URL se configura automáticamente en Jenkins vía JCasC (`jenkins.yaml`) bajo `globalLibraries`:

```yaml
# docker/jenkins.yaml (fragmento)
unclassified:
  globalLibraries:
    libraries:
      - name: "controlstock-shared-lib"
        retriever:
          modernSCM:
            scm:
              git:
                remote: "${SHARED_LIBRARY_REPO}"
                credentialsId: "gitops-git-credentials"
        defaultVersion: "main"
        implicit: false
        allowVersionOverride: true
```

---

## Paso 2 — Construir y Publicar Imagen del Controller

El controller Jenkins utiliza una imagen personalizada que incluye herramientas adicionales (Maven, kubectl, Helm, Trivy, gitleaks) preinstaladas para reducir el tiempo de inicio de los agentes.

### Construcción local

```bash
# Desde la raíz del proyecto
cd jenkins-shared-library/docker/

# Construir imagen
docker build \
  -t controlstock-jenkins:latest \
  -f Dockerfile .

# Etiquetar para el registry Gitea
docker tag controlstock-jenkins:latest \
  <VPS_IP>:3000/controlstock/controlstock-jenkins:latest

# Hacer push al registry Gitea (HTTP insecure en local)
docker push <VPS_IP>:3000/controlstock/controlstock-jenkins:latest
```

> **Nota:** Para que `docker push` funcione contra un registry HTTP en local, agregar al `/etc/docker/daemon.json`:
> ```json
> {
>   "insecure-registries": ["<VPS_IP>:3000"]
> }
> ```

### Actualizar el pod Jenkins en K3s

Después de publicar la nueva imagen, reiniciar el deployment para que K3s use la imagen actualizada:

```bash
kubectl rollout restart deployment/jenkins -n cicd \
  --kubeconfig ~/.kube/config-controlstock-local

# Verificar que el pod se reinicia correctamente
kubectl rollout status deployment/jenkins -n cicd \
  --kubeconfig ~/.kube/config-controlstock-local \
  --timeout=120s
```

### Verificación

```bash
# Confirmar imagen en uso
kubectl get pod -n cicd -l app=jenkins \
  -o jsonpath='{.items[0].spec.containers[0].image}'
# Salida esperada: <VPS_IP>:3000/controlstock/controlstock-jenkins:latest
```

---

## Paso 3 — Bootstrap del Cluster (Namespace + ServiceAccount)

Los agentes Jenkins se ejecutan como pods efímeros en el namespace `jenkins` del cluster K3s. Este paso crea el namespace y los recursos RBAC necesarios para que el controller pueda crear, monitorear y eliminar pods de agente.

### Aplicar RBAC

```bash
kubectl \
  --kubeconfig ~/.kube/config-controlstock-local \
  apply -f terraform/environments/argocd-bootstrap/jenkins-agent-rbac-local.yaml
```

### Contenido de `jenkins-agent-rbac-local.yaml`

```yaml
---
apiVersion: v1
kind: Namespace
metadata:
  name: jenkins

---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: jenkins-agent
  namespace: jenkins

---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: jenkins-agent-role
rules:
  - apiGroups: [""]
    resources: ["pods", "pods/log", "pods/exec", "configmaps", "secrets"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
  - apiGroups: ["apps"]
    resources: ["deployments", "replicasets"]
    verbs: ["get", "list", "watch"]

---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: jenkins-agent-binding
subjects:
  - kind: ServiceAccount
    name: jenkins-agent
    namespace: jenkins
roleRef:
  kind: ClusterRole
  name: jenkins-agent-role
  apiGroup: rbac.authorization.k8s.io
```

### Verificación

```bash
# Verificar namespace creado
kubectl get namespace jenkins \
  --kubeconfig ~/.kube/config-controlstock-local

# Verificar ServiceAccount
kubectl get serviceaccount jenkins-agent -n jenkins \
  --kubeconfig ~/.kube/config-controlstock-local

# Verificar ClusterRoleBinding
kubectl get clusterrolebinding jenkins-agent-binding \
  --kubeconfig ~/.kube/config-controlstock-local
```

---

## Paso 4 — Proveer Variables de Entorno y Credenciales al Controller (JCasC)

Jenkins Configuration as Code (JCasC) permite inyectar toda la configuración del controller de forma declarativa a través del archivo `jenkins.yaml`. Las variables de entorno se inyectan al pod Jenkins como `env` en el manifiesto K3s.

### Variables de entorno del controller

| Variable | Valor local | Descripción |
|----------|-------------|-------------|
| `GITEA_REGISTRY` | `<VPS_IP>:3000/controlstock` | Registry de imágenes Docker |
| `K3S_API_SERVER` | `https://<VPS_IP>:6443` | URL del API server de K3s |
| `K3S_CLUSTER_NAME` | `k3s-controlstock-local` | Nombre del cluster K3s |
| `REGISTRY_INSECURE` | `true` (local) / `false` (prod) | Permite registry HTTP sin TLS |
| `SMOKE_USE_INCLUSTER` | `true` (local) / `false` (prod) | Smoke tests usan DNS in-cluster |
| `JENKINS_URL` | `http://<VPS_IP>:8080` | URL pública del controller |
| `JENKINS_TUNNEL` | `<VPS_IP>:50000` | Tunnel JNLP para agentes |
| `VAULT_ADDR` | `http://vault.secrets.svc.cluster.local:8200` | Vault interno K3s |
| `SHARED_LIBRARY_REPO` | `http://<VPS_IP>:3000/controlstock/jenkins-shared-library.git` | URL de la Shared Library |
| `SONAR_URL` | `http://sonarqube.cicd.svc.cluster.local:9000` | SonarQube pod en K3s |
| `SLACK_TEAM` | *(vacío en local)* | Workspace Slack (opcional) |
| `GITOPS_GIT_USERNAME` | `gitea-admin` *(auto)* | Usuario GitOps para helm charts |
| `GITOPS_GIT_TOKEN` | `gitea-admin` *(auto)* | Token GitOps para helm charts |

### Auto-completado en ambiente local

El script `setup-cicd-pipeline.sh` rellena automáticamente:

```bash
# SONAR_URL y SONAR_TOKEN desde el pod SonarQube
SONAR_URL=$(kubectl get svc sonarqube -n cicd \
  -o jsonpath='http://{.spec.clusterIP}:9000')
SONAR_TOKEN=$(curl -s -u admin:admin \
  "${SONAR_URL}/api/user_tokens/generate" \
  -d "name=jenkins-token" | jq -r '.token')

# VAULT_TOKEN desde vault-init.json generado en Etapa 0
VAULT_TOKEN=$(jq -r '.root_token' ~/.vault/vault-init.json)

# GITOPS credentials fijas para local
GITOPS_GIT_USERNAME="gitea-admin"
GITOPS_GIT_TOKEN="gitea-admin"
```

### Credenciales (JCasC credentials store)

Las siguientes credenciales se configuran en Jenkins vía JCasC y se almacenan de forma segura:

| ID de credencial | Tipo | Descripción | Auto en local |
|-----------------|------|-------------|--------------|
| `sonar-token` | Secret Text | Token de autenticación SonarQube | Sí |
| `slack-token` | Secret Text | Bot Token de Slack | No (opcional) |
| `k3s-kubeconfig` | Secret File | kubeconfig del cluster K3s | Sí |
| `gitea-registry-credentials` | Username/Password | Usuario y contraseña del registry Gitea | Sí |
| `gitops-git-credentials` | Username/Password | Credenciales para push a helm-charts | Sí |
| `vault-token` | Secret Text | Token root de HashiCorp Vault | Sí |

### Fragmento JCasC para credenciales

```yaml
# docker/jenkins.yaml (fragmento credentials)
credentials:
  system:
    domainCredentials:
      - credentials:
          - string:
              id: "sonar-token"
              secret: "${SONAR_TOKEN}"
              description: "SonarQube authentication token"
          - usernamePassword:
              id: "gitea-registry-credentials"
              username: "gitea-admin"
              password: "${GITEA_REGISTRY_PASSWORD}"
              description: "Gitea Docker registry credentials"
          - usernamePassword:
              id: "gitops-git-credentials"
              username: "${GITOPS_GIT_USERNAME}"
              password: "${GITOPS_GIT_TOKEN}"
              description: "GitOps credentials for helm-charts push"
          - string:
              id: "vault-token"
              secret: "${VAULT_TOKEN}"
              description: "HashiCorp Vault root token"
          - file:
              id: "k3s-kubeconfig"
              fileName: "kubeconfig"
              secretBytes: "${readFileBase64('/root/.kube/config-controlstock-local')}"
              description: "K3s cluster kubeconfig"
```

### Aplicar la configuración JCasC

```bash
# Copiar jenkins.yaml al ConfigMap del pod Jenkins
kubectl create configmap jenkins-casc-config \
  --from-file=jenkins.yaml=jenkins-shared-library/docker/jenkins.yaml \
  -n cicd \
  --kubeconfig ~/.kube/config-controlstock-local \
  --dry-run=client -o yaml | kubectl apply -f -

# Recargar JCasC sin reiniciar el pod (si Jenkins ya está corriendo)
curl -s -X POST \
  "http://<VPS_IP>:8080/configuration-as-code/reload" \
  --user "admin:$(kubectl get secret jenkins-admin -n cicd \
    -o jsonpath='{.data.password}' | base64 -d)"
```

---

## Paso 5 — Crear los Jobs de Pipeline en Jenkins y los Webhooks de Gitea

### Tipo de job: Multibranch Pipeline

Cada microservicio tiene su propio **Multibranch Pipeline** en Jenkins. Este tipo de job:

1. Escanea automáticamente todas las ramas del repositorio Gitea.
2. Crea un pipeline independiente por rama que contenga un `Jenkinsfile`.
3. Es disparado por el plugin `multibranch-scan-webhook-trigger` cuando Gitea envía un webhook.

### Trigger: multibranch-scan-webhook-trigger

El trigger se configura con un token único por repositorio:

```
Webhook URL: http://<VPS_IP>:8080/multibranch-webhook-trigger/invoke?token=<repo-name>
```

Ejemplo para `iam-service`:
```
http://<VPS_IP>:8080/multibranch-webhook-trigger/invoke?token=iam-service
```

### Tabla de jobs de Jenkins

| Job Name | Repositorio Gitea | SERVICE_NAME default |
|----------|-------------------|---------------------|
| `iam-service` | `controlstock/iam-service` | `iam-service` |
| `catalog-service` | `controlstock/catalog-service` | `catalog-service` |
| `inventory-service` | `controlstock/inventory-service` | `inventory-service` |
| `adjustment-service` | `controlstock/adjustment-service` | `adjustment-service` |
| `alert-service` | `controlstock/alert-service` | `alert-service` |
| `supplier-service` | `controlstock/supplier-service` | `supplier-service` |
| `report-service` | `controlstock/report-service` | `report-service` |
| `audit-service` | `controlstock/audit-service` | `audit-service` |
| `integration-service` | `controlstock/integration-service` | `integration-service` |
| `report-etl-service` | `controlstock/report-etl-service` | `report-etl-service` |
| `controlstock-web` | `controlstock/controlstock-web` | `controlstock-web` |
| `controlstock-migrations` | `controlstock/controlstock-migrations` | — (pipeline de migraciones, Paso 6b) |

> El job `controlstock-migrations` es también un Multibranch Pipeline, pero usa el `Jenkinsfile` de migraciones (Paso 6b) en lugar del de build de servicio, y su webhook se dispara solo en `push`.

### Creación automática de jobs via Groovy Script (/scriptText)

En ambiente local, el script `setup-cicd-pipeline.sh` crea todos los jobs enviando un script Groovy al endpoint `/scriptText` de Jenkins:

```groovy
// Groovy script para crear un Multibranch Pipeline (ejemplo iam-service)
import jenkins.model.*
import org.jenkinsci.plugins.workflow.multibranch.*
import com.cloudbees.hudson.plugins.folder.*

def jenkins = Jenkins.instance
def jobName = "iam-service"
def gitUrl = "http://<VPS_IP>:3000/controlstock/iam-service.git"
def webhookToken = "iam-service"

// Crear el job Multibranch Pipeline
def xmlConfig = """
<org.jenkinsci.plugins.workflow.multibranch.WorkflowMultiBranchProject>
  <sources>
    <data>
      <jenkins.branch.BranchSource>
        <source class="jenkins.plugins.git.GitSCMSource">
          <remote>${gitUrl}</remote>
          <credentialsId>gitops-git-credentials</credentialsId>
        </source>
      </jenkins.branch.BranchSource>
    </data>
  </sources>
  <triggers>
    <com.igalg.jenkins.plugins.mswt.trigger.ComputedFolderWebHookTrigger>
      <spec></spec>
      <token>${webhookToken}</token>
    </com.igalg.jenkins.plugins.mswt.trigger.ComputedFolderWebHookTrigger>
  </triggers>
</org.jenkinsci.plugins.workflow.multibranch.WorkflowMultiBranchProject>
"""
jenkins.createProjectFromXML(jobName, new ByteArrayInputStream(xmlConfig.bytes))
jenkins.save()
```

### Creación de webhooks en Gitea

Para cada repositorio (excepto `jenkins-shared-library`), el script crea un webhook en Gitea:

```bash
# Crear webhook para iam-service (eventos: push y pull_request)
curl -s -X POST \
  "http://<VPS_IP>:3000/api/v1/repos/controlstock/iam-service/hooks" \
  -H "Content-Type: application/json" \
  -u "gitea-admin:gitea-admin" \
  -d '{
    "type": "gitea",
    "config": {
      "url": "http://<VPS_IP>:8080/multibranch-webhook-trigger/invoke?token=iam-service",
      "content_type": "json"
    },
    "events": ["push", "pull_request"],
    "active": true
  }'
```

> **Exclusión:** El repositorio `jenkins-shared-library` **NO** recibe webhook de pipeline. Los cambios en la shared library se aplican en el próximo build de cada microservicio que la usa.

### Verificación de jobs y webhooks

```bash
# Verificar jobs creados en Jenkins
curl -s "http://<VPS_IP>:8080/api/json?tree=jobs[name]" \
  --user "admin:<password>" | jq '.jobs[].name'

# Verificar webhooks en Gitea para iam-service
curl -s \
  "http://<VPS_IP>:3000/api/v1/repos/controlstock/iam-service/hooks" \
  -u "gitea-admin:gitea-admin" | jq '.[].config.url'
```

---

## Paso 6 — Bootstrap de ArgoCD (ApplicationSet por Servicio)

ArgoCD gestiona el despliegue continuo de todos los microservicios usando **ApplicationSet** con el generador Git.

### Comando de bootstrap

```bash
kubectl \
  --kubeconfig ~/.kube/config-controlstock-local \
  apply -f terraform/environments/argocd-bootstrap/
```

Este directorio contiene:

```
terraform/environments/argocd-bootstrap/
├── argocd-project.yaml              # AppProject controlstock
├── argocd-applicationset.yaml       # ApplicationSet con Git generator
├── jenkins-agent-rbac-local.yaml    # RBAC para agentes Jenkins
└── argocd-image-updater-cm.yaml     # ConfigMap opcional
```

### ApplicationSet con Git Generator

El ApplicationSet usa el **Git generator** para auto-descubrir charts en el repositorio `controlstock-helm-charts`:

```yaml
# argocd-applicationset.yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: controlstock-services
  namespace: argocd
spec:
  generators:
    - git:
        repoURL: http://<VPS_IP>:3000/controlstock/controlstock-helm-charts.git
        revision: main
        directories:
          - path: "charts/*"
  template:
    metadata:
      name: "{{path.basename}}"
      namespace: argocd
      labels:
        app.kubernetes.io/part-of: controlstock
    spec:
      project: controlstock
      source:
        repoURL: http://<VPS_IP>:3000/controlstock/controlstock-helm-charts.git
        targetRevision: main
        path: "{{path}}"
        helm:
          valueFiles:
            - values-local.yaml
      destination:
        server: https://kubernetes.default.svc
        namespace: apps
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
          - CreateNamespace=true
```

### Políticas de sincronización por ambiente

| Ambiente | Tipo de Sync | Auto-prune | Self-heal | Aprobación requerida |
|----------|-------------|------------|-----------|---------------------|
| `local` / `dev` | Automated | Sí | Sí | No |
| `staging` | Automated | Sí | No | No |
| `prod` | Manual (UI ArgoCD) | No | No | Sí (aprobación manual) |

### AppProject controlstock

```yaml
# argocd-project.yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: controlstock
  namespace: argocd
spec:
  description: "ControlStock — Sistema de Gestión de Inventario Retail"
  sourceRepos:
    - "http://<VPS_IP>:3000/controlstock/*"
  destinations:
    - namespace: apps
      server: https://kubernetes.default.svc
    - namespace: "controlstock-*"
      server: https://kubernetes.default.svc
  clusterResourceWhitelist:
    - group: ""
      kind: Namespace
  namespaceResourceWhitelist:
    - group: "*"
      kind: "*"
```

### Verificación de ArgoCD

```bash
# Listar aplicaciones ArgoCD
kubectl get applications -n argocd \
  --kubeconfig ~/.kube/config-controlstock-local

# Salida esperada (una app por servicio):
# NAME                    SYNC STATUS   HEALTH STATUS
# iam-service             Synced        Healthy
# catalog-service         Synced        Healthy
# ...

# Ver detalles de una aplicación
kubectl describe application iam-service -n argocd \
  --kubeconfig ~/.kube/config-controlstock-local
```

---

## Paso 6b — Pipeline de Migraciones de Base de Datos (Liquibase)

Las migraciones de esquema **no se acoplan al build de cada microservicio**. Viven en el repositorio dedicado `controlstock-migrations` (un directorio `<servicio>/changelog/` por bounded context, con `root.yaml` + changelogs numerados `00001_*.yaml`). Los microservicios Spring Boot corren con `spring.liquibase.enabled=false`: el esquema se aplica desde fuera del JAR, **antes** de que ArgoCD despliegue la nueva versión de los pods. Esto garantiza trazabilidad por PR sobre el repo de migraciones y evita carreras esquema/aplicación.

La **primera** aplicación de migraciones se hace manualmente con `.claude/scripts/run-liquibase-migrations.sh` (bootstrap, desde fuera del cluster). A partir de ahí, **cada push al repo `controlstock-migrations` dispara este pipeline**, que detecta qué servicios cambiaron y aplica únicamente sus changelogs.

### Estrategia de disparo

```
  CÓDIGO DE SERVICIO                          MIGRACIONES DE BD
  git push (dev) repo <svc>                   git push repo controlstock-migrations
       │                                            │
       ▼                                            ▼
  [Gitea webhook]                             [Gitea webhook]
       │                                            │
       ▼                                            ▼
  [Jenkins Multibranch: <svc>]                [Jenkins Multibranch: controlstock-migrations]
       │                                            │
  ┌────┴──────────────────────────┐           ┌────┴───────────────────────────────┐
  │ build → tests → image → ...    │           │ detectChangedServices →            │
  │ → bumpImageTag → smoke → notify│           │ runDatabaseMigration (Liquibase     │
  └────┬──────────────────────────┘           │   update, container in-cluster) →   │
       │ (git push helm-charts)                │ notify                              │
       │                                       └────┬───────────────────────────────┘
       ▼                                            │ (esquema actualizado en ns data)
  [ArgoCD Git Generator] ◀── orden recomendado: migración antes del rollout ──┘
       │
       ▼
  [K3s VPS — Namespace apps]
```

> **Orden esquema-antes-de-pods.** En `local`/`dev` (ArgoCD auto-sync) basta con que la migración corra primero porque las migraciones son aditivas y compatibles hacia atrás (expand-then-contract). Para `prod` se recomienda además el **hook PreSync de ArgoCD** (ver abajo), que hace el orden explícito y bloqueante.

### Mapeo servicio → base de datos

El pipeline deriva la BD destino como `controlstock_<slug>` (slug = nombre del servicio sin sufijo `-service`), con dos excepciones gestionadas por overrides:

| Servicio (dir en repo) | Base de datos | Usuario | Nota |
|---|---|---|---|
| `iam-service` | `controlstock_iam` | `controlstock_iam_user` | + seed de 7 roles (`00002_seed_roles.yaml`) |
| `catalog-service` | `controlstock_catalog` | `controlstock_catalog_user` | |
| `inventory-service` | `controlstock_inventory` | `controlstock_inventory_user` | |
| `adjustment-service` | `controlstock_adjustment` | `controlstock_adjustment_user` | |
| `alert-service` | `controlstock_alert` | `controlstock_alert_user` | |
| `supplier-service` | `controlstock_supplier` | `controlstock_supplier_user` | |
| `report-service` | `controlstock_reporting` | `controlstock_reporting_user` | **override**: el slug `report` ≠ nombre de BD real |
| `audit-service` | `controlstock_audit` | `controlstock_audit_user` | |
| `integration-service` | `controlstock_integration` | `controlstock_integration_user` | |
| `report-etl-service` | — | — | **sin BD propia** (Spark ETL; lee read model Mongo + JDBC a reporting/audit). No migra. |

### Step de la Shared Library: `runDatabaseMigration.groovy`

Corre Liquibase directamente desde un container `liquibase` del pod-agente (el agente está dentro del cluster, así que alcanza `postgresql.data.svc.cluster.local` por DNS; no necesita el baile ConfigMap+Job que sí requiere el script de bootstrap externo). Aplica el fix de `--searchPath` + changelog relativo (Liquibase 4.x falla con `root.yaml does not exist` si se pasa una ruta absoluta a `--changeLogFile`).

```groovy
// vars/runDatabaseMigration.groovy
def call(Map config = [:]) {
    def service = config.service                                   // p.ej. "iam-service"
    def slug    = service.replaceAll(/-service$/, '').replaceAll('-', '_')
    def dbName  = config.dbName  ?: "controlstock_${slug}"         // override p.ej. controlstock_reporting
    def dbUser  = config.dbUser  ?: "${dbName}_user"
    def credId  = config.dbCredId ?: "db-${slug}"                 // credencial Jenkins (password), respaldada por Vault
    def changelogDir = "${env.WORKSPACE}/${service}/changelog"

    if (!fileExists("${changelogDir}/root.yaml")) {
        error("runDatabaseMigration: no existe ${changelogDir}/root.yaml para ${service}")
    }

    container('liquibase') {
        withCredentials([string(credentialsId: credId, variable: 'DB_PASSWORD')]) {
            sh """
                liquibase \
                  --searchPath='${changelogDir}' \
                  --changeLogFile=root.yaml \
                  --url='jdbc:postgresql://postgresql.data.svc.cluster.local:5432/${dbName}' \
                  --username='${dbUser}' \
                  --password="\$DB_PASSWORD" \
                  --logLevel=info \
                  update
            """
        }
    }
    echo "[DB-MIGRATION] ${service} → ${dbName}: OK"
}
```

Añadir el pod-template `resources/org/controlstock/podMigrations.yaml`:

```yaml
# resources/org/controlstock/podMigrations.yaml
apiVersion: v1
kind: Pod
spec:
  serviceAccountName: jenkins-agent
  containers:
    - name: liquibase
      image: liquibase/liquibase:4.27
      command: ["sleep"]
      args: ["infinity"]
      resources:
        requests: { cpu: "100m", memory: "256Mi" }
        limits:   { cpu: "500m", memory: "512Mi" }
    - name: jnlp
      image: jenkins/inbound-agent:latest
```

### Jenkinsfile del repositorio `controlstock-migrations`

Detecta los servicios cuyos changelogs cambiaron en el push (`git diff`) y aplica solo esos. Idempotente: Liquibase omite los changesets ya registrados en `databasechangelog`.

```groovy
// controlstock-migrations/Jenkinsfile
@Library('controlstock-shared-lib') _

// BD destino cuando el slug != nombre de BD real
def DB_OVERRIDES = ['report-service': 'controlstock_reporting']
// Servicios sin BD propia (no migran)
def NO_DB = ['report-etl-service']

pipeline {
  agent {
    kubernetes { yaml libraryResource('org/controlstock/podMigrations.yaml') }
  }
  options { timestamps(); ansiColor('xterm') }
  stages {
    stage('Detect Changed Services') {
      steps {
        script {
          // En el primer build de la rama no hay HEAD~1: migra todo el árbol
          def diffCmd = sh(returnStatus: true, script: 'git rev-parse HEAD~1') == 0 ?
              'git diff --name-only HEAD~1 HEAD' : 'git ls-files'
          def dirs = sh(returnStdout: true,
              script: "${diffCmd} | grep '/changelog/' | cut -d/ -f1 | sort -u || true").trim()
          def svcs = dirs ? dirs.split('\\n').findAll { it && it.endsWith('-service') && !(it in NO_DB) } : []
          env.CHANGED_SERVICES = svcs.join(' ')
          echo "Servicios con migraciones a aplicar: ${env.CHANGED_SERVICES ?: '(ninguno)'}"
        }
      }
    }
    stage('Run Migrations') {
      when { expression { env.CHANGED_SERVICES?.trim() } }
      steps {
        script {
          for (svc in env.CHANGED_SERVICES.split(' ')) {
            if (svc) { runDatabaseMigration(service: svc, dbName: DB_OVERRIDES[svc]) }
          }
        }
      }
    }
  }
  post { always { notify(status: currentBuild.currentResult) } }
}
```

### Creación del job y webhook de migraciones

El job se crea igual que los demás Multibranch (Paso 5), apuntando al repo `controlstock-migrations` con token `controlstock-migrations`:

```bash
# Webhook en Gitea para el repo de migraciones (solo eventos push)
curl -s -X POST \
  "http://<VPS_IP>:3000/api/v1/repos/controlstock/controlstock-migrations/hooks" \
  -H "Content-Type: application/json" \
  -u "gitea-admin:gitea-admin" \
  -d '{
    "type": "gitea",
    "config": {
      "url": "http://<VPS_IP>:8080/multibranch-webhook-trigger/invoke?token=controlstock-migrations",
      "content_type": "json"
    },
    "events": ["push"],
    "active": true
  }'
```

> A diferencia de los repos de servicio, el de migraciones se dispara **solo en `push`** (no en `pull_request`): las migraciones se aplican cuando se mergea a la rama, no en cada PR abierto.

### Credenciales de base de datos

El step lee la contraseña desde una credencial Jenkins `db-<slug>` (tipo *Secret text*), respaldada por Vault en `secret/controlstock/<servicio>/db`. En `local`/`dev` el valor por defecto es `changeme_<slug>` (creado por `init-databases.sh`); **rotar vía Vault antes de `prod`**. Para `report-service` la credencial es `db-report` apuntando al password de `controlstock_reporting_user` (`changeme_reporting` en local).

```yaml
# docker/jenkins.yaml (fragmento credentials — una por BD)
credentials:
  system:
    domainCredentials:
      - credentials:
          - string:
              scope: GLOBAL
              id: "db-iam"
              secret: "${DB_IAM_PASSWORD}"
              description: "Password controlstock_iam_user"
          # ... db-catalog, db-inventory, ..., db-report (controlstock_reporting_user)
```

### Alternativa GitOps recomendada para `prod`: hook PreSync de ArgoCD

Para hacer el orden esquema-antes-de-pods **explícito y bloqueante** en `prod`, el chart Helm de cada servicio puede incluir un `Job` de migración anotado como hook PreSync. ArgoCD lo ejecuta y espera su éxito antes de aplicar el `Deployment`. El changelog se entrega como imagen `controlstock-migrations:<servicio>-<tag>` construida por este pipeline (changelogs horneados), o vía initContainer que clona el repo.

```yaml
# helm/<service>/templates/migration-job.yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: {{ .Release.Name }}-liquibase-{{ .Values.image.tag | default "latest" }}
  annotations:
    argocd.argoproj.io/hook: PreSync
    argocd.argoproj.io/hook-delete-policy: HookSucceeded
spec:
  backoffLimit: 1
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: liquibase
          image: liquibase/liquibase:4.27
          args:
            - "--searchPath=/liquibase/changelog"
            - "--changeLogFile=root.yaml"
            - "--url=jdbc:postgresql://postgresql.data.svc.cluster.local:5432/{{ .Values.db.name }}"
            - "--username={{ .Values.db.user }}"
            - "--password=$(DB_PASSWORD)"
            - "update"
          env:
            - name: DB_PASSWORD
              valueFrom:
                secretKeyRef: { name: {{ .Values.db.secret }}, key: password }
          volumeMounts:
            - { name: changelog, mountPath: /liquibase/changelog }
      volumes:
        - name: changelog
          configMap: { name: {{ .Release.Name }}-changelog }
```

> En `local`/`dev` se prefiere el pipeline Jenkins (feedback más rápido y desacoplado del rollout). En `prod` el hook PreSync añade la garantía de orden bajo sync manual.

### Verificación de la etapa de migraciones

```bash
# 1. Cambiar un changelog y pushear (dispara el job de migraciones)
git clone http://gitea-admin:gitea-admin@<VPS_IP>:3000/controlstock/controlstock-migrations.git
cd controlstock-migrations
# (editar p.ej. catalog-service/changelog/00002_*.yaml)
git add -A && git commit -m "feat(catalog): nueva migración" && git push

# 2. Confirmar que el job de Jenkins corrió y aplicó solo catalog-service
curl -s "http://<VPS_IP>:8080/job/controlstock-migrations/job/main/lastBuild/consoleText" \
  --user "admin:<password>" | grep "DB-MIGRATION"

# 3. Confirmar el changeset en la BD
kubectl exec -n data postgresql-0 -- \
  env PGPASSWORD=changeme_pg_admin psql -U postgres -d controlstock_catalog \
  -tAc "SELECT id, dateexecuted FROM databasechangelog ORDER BY orderexecuted DESC LIMIT 3;"
```

---

## Verificación del Pipeline Completo

Para verificar que el pipeline CI/CD funciona de extremo a extremo, realizar un commit trivial en `iam-service`.

### Procedimiento de prueba

```bash
# 1. Clonar el repositorio iam-service
git clone http://gitea-admin:gitea-admin@<VPS_IP>:3000/controlstock/iam-service.git
cd iam-service

# 2. Crear rama dev (si no existe)
git checkout -b dev

# 3. Hacer un cambio trivial
echo "# CI/CD verification commit" >> README.md
git add README.md
git commit -m "chore: verify CI/CD pipeline"

# 4. Push (dispara webhook → Jenkins)
git push origin dev
```

### Checklist de stages en Jenkins

Una vez disparado el pipeline, verificar en `http://<VPS_IP>:8080/job/iam-service/` que los siguientes stages aparecen como exitosos:

- [ ] **Compute Tag** — Tag calculado y publicado como variable de entorno
- [ ] **Build** — `mvn clean package` exitoso
- [ ] **Integration Tests** — `mvn test -Pintegration` exitoso
- [ ] **Quality Gates** — SonarQube Quality Gate: `Passed`
- [ ] **Security Scans** — OWASP Dependency-Check: sin CVEs críticos; gitleaks: sin secretos detectados
- [ ] **Build & Push Image** — Imagen publicada en `<VPS_IP>:3000/controlstock/iam-service:<tag>`
- [ ] **Scan Image** — Trivy: sin CVEs CRITICAL
- [ ] **Bump Image Tag** — Commit en `controlstock-helm-charts` con nuevo tag
- [ ] **Smoke Tests** — `/actuator/health/readiness` y `/actuator/prometheus` responden 200
- [ ] **Notify** — Log de resultado (Slack si está configurado)

### Verificación ArgoCD

```bash
# Verificar que ArgoCD detectó el cambio y sincronizó
kubectl get application iam-service -n argocd \
  -o jsonpath='{.status.sync.status}' \
  --kubeconfig ~/.kube/config-controlstock-local
# Salida esperada: Synced

# Verificar que el pod está corriendo con el nuevo tag
kubectl get pod -n apps -l app.kubernetes.io/name=iam-service \
  -o jsonpath='{.items[0].spec.containers[0].image}' \
  --kubeconfig ~/.kube/config-controlstock-local
```

---

## Criterios de Aceptación

Los siguientes criterios deben cumplirse para considerar esta etapa completa.

### Infraestructura CI/CD

| # | Criterio | Verificación | Modo |
|---|----------|-------------|------|
| 1 | Shared Library generada y publicada en Gitea | `http://<VPS_IP>:3000/controlstock/jenkins-shared-library` accesible | ✓ auto (local) |
| 2 | Imagen `controlstock-jenkins:latest` publicada en registry Gitea | `docker pull <VPS_IP>:3000/controlstock/controlstock-jenkins:latest` exitoso | ✓ auto (local) |
| 3 | Pod Jenkins corriendo con imagen personalizada | `kubectl get pod -n cicd -l app=jenkins` → Running | ✓ auto (local) |
| 4 | Namespace `jenkins` creado en K3s | `kubectl get namespace jenkins` → Active | ✓ auto (local) |
| 5 | ServiceAccount `jenkins-agent` creado en namespace `jenkins` | `kubectl get sa jenkins-agent -n jenkins` | ✓ auto (local) |

### Jobs de Jenkins

| # | Criterio | Verificación | Modo |
|---|----------|-------------|------|
| 6 | 12 jobs Multibranch Pipeline creados en Jenkins (11 servicios/web + `controlstock-migrations`) | `curl .../api/json` devuelve 12 jobs | ✓ auto (local) |
| 7 | Todos los jobs reconocen la Shared Library | Primer build muestra `Loading shared library controlstock-shared-lib` | ✓ auto (local) |
| 8 | Webhooks configurados en Gitea para todos los repos (excepto shared-lib); `controlstock-migrations` solo en `push` | `GET /api/v1/repos/.../hooks` devuelve webhook activo | ✓ auto (local) |
| 9 | Job `report-etl-service` usa `buildScalaBatchJob` (sbt) | Jenkinsfile tiene `buildScalaBatchJob()` | □ manual |

### Integración Jenkins-K3s

| # | Criterio | Verificación | Modo |
|---|----------|-------------|------|
| 10 | Agentes Jenkins se crean como pods en namespace `jenkins` | Al ejecutar un build: `kubectl get pods -n jenkins` muestra pod efímero | ✓ auto (local) |
| 11 | Agentes usan `podBackend.yaml` para Spring Boot | Pod tiene containers `maven` y `kaniko` | ✓ auto (local) |
| 12 | Agentes usan `podFrontend.yaml` para Next.js | Pod tiene container `node` | ✓ auto (local) |
| 13 | Agentes usan `podScalaBatch.yaml` para report-etl-service | Pod tiene container `sbt-scala` | ✓ auto (local) |

### Pipeline CI funcional

| # | Criterio | Verificación | Modo |
|---|----------|-------------|------|
| 14 | Stage `Compute Tag` genera tag único y reproducible | Build log muestra `IMAGE_TAG=dev-<hash>` | ✓ auto (local) |
| 15 | Stage `Build` compila correctamente con Maven 3.9 / Java 21 | Stage verde en BlueOcean | ✓ auto (local) |
| 16 | Stage `Integration Tests` pasa (Testcontainers en pod) | Stage verde; JUnit report publicado | ✓ auto (local) |
| 17 | Stage `Quality Gates` comunica con SonarQube in-cluster | Quality Gate status visible en SonarQube UI | ✓ auto (local) |
| 18 | Stage `Security Scans` ejecuta OWASP + gitleaks | Reportes HTML publicados en Jenkins | ✓ auto (local) |
| 19 | Stage `Build & Push Image` publica imagen con Kaniko | Imagen visible en Gitea registry | ✓ auto (local) |
| 20 | Stage `Scan Image` ejecuta Trivy y no bloquea en local | Reporte Trivy en log del build | ✓ auto (local) |
| 21 | Stage `Bump Image Tag` hace commit en helm-charts | Nuevo commit visible en `controlstock-helm-charts` | ✓ auto (local) |
| 22 | Stage `Smoke Tests` verifica `/actuator/health/readiness` 200 | Stage verde | ✓ auto (local) |
| 23 | Stage `Notify` no falla si `SLACK_TEAM` está vacío | Build status: SUCCESS incluso sin Slack | ✓ auto (local) |

### ArgoCD y despliegue

| # | Criterio | Verificación | Modo |
|---|----------|-------------|------|
| 24 | ArgoCD ApplicationSet creado y descubriendo charts | `kubectl get applicationset -n argocd` | ✓ auto (local) |
| 25 | ArgoCD detecta commit de `bumpImageTag` y sincroniza | App status: `Synced` + `Healthy` | ✓ auto (local) |
| 26 | Pod del servicio desplegado con nueva imagen en namespace `apps` | `kubectl get pod -n apps` muestra nuevo pod | ✓ auto (local) |
| 27 | Sync manual configurado para ambiente `prod` | AppProject/Application prod tiene `syncPolicy: {}` | □ manual (prod) |

### Seguridad y credenciales

| # | Criterio | Verificación | Modo |
|---|----------|-------------|------|
| 28 | Credencial `sonar-token` configurada en Jenkins | Jenkins credentials store visible | ✓ auto (local) |
| 29 | Credencial `vault-token` configurada en Jenkins | Jenkins credentials store visible | ✓ auto (local) |
| 30 | Credencial `gitops-git-credentials` configurada | Jenkins credentials store visible | ✓ auto (local) |
| 31 | Credencial `k3s-kubeconfig` configurada | Jenkins credentials store visible | ✓ auto (local) |
| 32 | Pipeline NO expone secretos en logs | Logs no contienen tokens en texto plano | □ revisión manual |
| 33 | Credenciales `db-<slug>` (una por BD) configuradas, respaldadas por Vault | Jenkins credentials store muestra `db-iam`, `db-catalog`, …, `db-report` | ✓ auto (local) |

### Migraciones de Base de Datos (Liquibase)

| # | Criterio | Verificación | Modo |
|---|----------|-------------|------|
| 34 | Migración inicial (bootstrap) aplicada en las 9 BDs | `databasechangelog` existe en cada `controlstock_*` (30 tablas de dominio; iam con 7 roles) | ✓ manual (bootstrap) |
| 35 | Job `controlstock-migrations` creado con su `Jenkinsfile` de migraciones | `http://<VPS_IP>:8080/job/controlstock-migrations/` existe | ✓ auto (local) |
| 36 | Webhook `push` del repo `controlstock-migrations` dispara el job | Push de un changelog lanza un build | ✓ auto (local) |
| 37 | Stage `Detect Changed Services` aplica solo los servicios con changelogs modificados | Build log lista los servicios cambiados | ✓ auto (local) |
| 38 | Stage `DB Migration` aplica Liquibase y es idempotente | Re-ejecutar sin cambios → `0 changesets`; nuevo registro en `databasechangelog` al cambiar | ✓ auto (local) |
| 39 | `report-service` migra contra `controlstock_reporting` (override) y `report-etl-service` NO migra | BD `controlstock_reporting` con `report_*`; sin BD `controlstock_report_etl` | ✓ auto (local) |
| 40 | (prod) Hook PreSync de ArgoCD ejecuta la migración antes del rollout | `Job` PreSync `Succeeded` antes del `Deployment` | □ manual (prod) |
