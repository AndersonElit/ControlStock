# Etapa 2 — Scaffolding de Proyectos

---

## 1. Objetivo

Generar la **estructura base de todos los proyectos** del sistema ControlStock mediante un único script que ejecuta de forma automatizada y secuencial los 13 pasos necesarios para tener todos los microservicios, el frontend, los changelogs Liquibase, los secretos en Vault y los repositorios en Gitea listos para el desarrollo.

Al finalizar esta etapa, el equipo de desarrollo tiene:

- 9 microservicios Spring Boot con arquitectura hexagonal completa (domain, application, infrastructure)
- 1 job Spark/Scala para el ETL de reportes
- 1 consumer OpenFaaS para generación de formatos de reporte
- 1 aplicación Next.js 14 como frontend
- Changelogs Liquibase iniciales con seed de datos para IAM
- Repositorios Git creados y con rama `main` pusheada en Gitea
- Secretos de conexión escritos en HashiCorp Vault KV v2 para cada servicio
- Helm charts configurados con observabilidad automática (Prometheus + OTEL)
- Pipelines Jenkins (Jenkinsfile) y Dockerfiles multi-stage por proyecto

---

## 2. Scaffolding de Microservicios y Frontend

### Comando de Ejecución Completo

```bash
bash .claude/scripts/scaffold-all-services.sh \
  -P controlstock \
  --vm-ip <VPS_IP> \
  -p controlstock \
  -m controlstock \
  -u controlstock_app \
  -w <contraseña-segura> \
  --backend iam-service:postgres:none:8081 \
  --backend catalog-service:postgres:kafka-producer:8082 \
  --backend inventory-service:postgres:kafka-producer,kafka-consumer:8083 \
  --backend adjustment-service:postgres:kafka-producer:8084 \
  --backend alert-service:postgres:kafka-consumer:8085 \
  --backend supplier-service:postgres:kafka-producer:8086 \
  --backend report-service:postgres:kafka-producer:8087 \
  --backend audit-service:postgres:kafka-consumer:8088 \
  --backend integration-service:postgres:kafka-producer,kafka-consumer:8089 \
  --bc-tags iam-service=BC-01 \
  --bc-tags catalog-service=BC-02 \
  --bc-tags inventory-service=BC-03 \
  --bc-tags adjustment-service=BC-04 \
  --bc-tags alert-service=BC-05 \
  --bc-tags supplier-service=BC-06 \
  --bc-tags report-service=BC-07 \
  --bc-tags audit-service=BC-08 \
  --bc-tags integration-service=BC-09 \
  --integration-service "notificaciones=BC-09,proveedor-rest=BC-09,proveedor-ftp=BC-09" \
  --saga-flows reposicion-inventario,ajuste-aprobado \
  --saga-participant inventory-service \
  --saga-participant adjustment-service \
  --outbox inventory-service \
  --outbox adjustment-service \
  --report-extraction report-etl-service:mongo:controlstock.reporting.parquet-generado \
  --report-types stock-actual,movimientos-periodo,auditoria-operaciones,proveedores-actividad \
  --report-schedule "0 2 * * *" \
  --report-formats xlsx,csv,pdf \
  --frontend controlstock-web
```

### Tabla de Servicios Generados

| Servicio | Puerto | Base de Datos | Mensajería | Módulos Generados |
|---|---|---|---|---|
| iam-service (BC-01) | 8081 | PostgreSQL `controlstock_iam` | — | domain, application, postgres-adapter, rest-api, helm, Jenkinsfile, Dockerfile |
| catalog-service (BC-02) | 8082 | PostgreSQL `controlstock_catalog` + MongoDB (proyector) | Kafka producer (outbox) | domain, application, postgres-adapter, mongo-adapter, kafka-producer, outbox-poller, rest-api, helm, Jenkinsfile, Dockerfile |
| inventory-service (BC-03) | 8083 | PostgreSQL `controlstock_inventory` + MongoDB (proyector) | Kafka producer (outbox) + consumer | domain, application, postgres-adapter, mongo-adapter, kafka-producer, kafka-consumer, outbox-poller, idempotency, rest-api, helm, Jenkinsfile, Dockerfile |
| adjustment-service (BC-04) | 8084 | PostgreSQL `controlstock_adjustment` | Kafka producer (outbox) | domain, application, postgres-adapter, kafka-producer, outbox-poller, idempotency, rest-api, helm, Jenkinsfile, Dockerfile |
| alert-service (BC-05) | 8085 | PostgreSQL `controlstock_alert` | Kafka consumer | domain, application, postgres-adapter, kafka-consumer, rest-api, helm, Jenkinsfile, Dockerfile |
| supplier-service (BC-06) | 8086 | PostgreSQL `controlstock_supplier` + MongoDB (proyector) | Kafka producer (outbox) | domain, application, postgres-adapter, mongo-adapter, kafka-producer, outbox-poller, rest-api, helm, Jenkinsfile, Dockerfile |
| report-service (BC-07) | 8087 | PostgreSQL `controlstock_reporting` | Kafka producer | domain, application, postgres-adapter, kafka-producer, rest-api, helm, Jenkinsfile, Dockerfile |
| audit-service (BC-08) | 8088 | PostgreSQL `controlstock_audit` | Kafka consumer | domain, application, postgres-adapter, kafka-consumer, rest-api, helm, Jenkinsfile, Dockerfile |
| integration-service (BC-09) | 8089 | PostgreSQL `controlstock_integration` | Kafka producer + consumer | domain, application, postgres-adapter, kafka-producer, kafka-consumer, outbox-poller, idempotency, camel-routes, lra-orchestrator, rest-api, helm, Jenkinsfile, Dockerfile |
| report-etl-service | — (CronJob) | MongoDB `controlstock_readmodel` (Spark) + JDBC | Kafka producer | Scala/sbt project, CronJob K8s, cronjob.yaml Helm, Jenkinsfile-batch, Dockerfile-spark |
| report-format-consumer | — (OpenFaaS) | MinIO | — | OpenFaaS function, handler.py, func.yaml |
| controlstock-web | — (Ingress) | — | — | Next.js 14, Helm chart, Jenkinsfile-frontend, Dockerfile-frontend |

### Creación de Repositorios en Gitea

El scaffold crea automáticamente un repositorio en Gitea para cada proyecto generado y realiza push de la rama `main` con el código inicial:

```
http://<VPS_IP>:3000/controlstock/iam-service
http://<VPS_IP>:3000/controlstock/catalog-service
http://<VPS_IP>:3000/controlstock/inventory-service
http://<VPS_IP>:3000/controlstock/adjustment-service
http://<VPS_IP>:3000/controlstock/alert-service
http://<VPS_IP>:3000/controlstock/supplier-service
http://<VPS_IP>:3000/controlstock/report-service
http://<VPS_IP>:3000/controlstock/audit-service
http://<VPS_IP>:3000/controlstock/integration-service
http://<VPS_IP>:3000/controlstock/report-etl-service
http://<VPS_IP>:3000/controlstock/report-format-consumer
http://<VPS_IP>:3000/controlstock/controlstock-web
```

### Observabilidad (Automática)

La observabilidad es inyectada automáticamente por el scaffold en todos los microservicios Spring Boot, sin necesidad de ningún paso manual:

- **logback-spring.xml**: generado con perfil `dev` (consola con patrón traceId/spanId) y perfil no-dev (LogstashEncoder JSON estructurado)
- **pom.xml**: dependencias de actuator, micrometer-registry-prometheus, micrometer-tracing-bridge-otel, opentelemetry-exporter-otlp y logstash-logback-encoder:7.4 añadidas automáticamente
- **application.yml**: bloque `management` completo con endpoints expuestos, métricas etiquetadas con `application` y `environment`, y sampling de trazas al 100%
- **deployment.yaml (Helm)**: anotaciones Prometheus scraping, init container `otel-agent`, variables de entorno OTEL (`OTEL_SERVICE_NAME`, `OTEL_EXPORTER_OTLP_ENDPOINT`, `JAVA_TOOL_OPTIONS`)
- **values-local.yaml y values-prod.yaml**: `otel.collectorEndpoint: http://tempo.observability.svc.cluster.local:4317`

---

### Backend Jenkinsfile — Spring Boot / Maven

Los pipelines de integración continua para microservicios Spring Boot utilizan la shared library Jenkins de ControlStock. Las etapas ejecutadas en orden son:

| Stage | Función Shared Library | Descripción |
|---|---|---|
| Compute Image Tag | `computeImageTag` | Calcula el tag de imagen Docker basado en `git rev-parse --short HEAD` + número de build |
| Build | `buildBackendService` | `mvn clean package -DskipTests`; valida que el fat JAR se genera correctamente |
| Integration Tests | `runIntegrationTests` | Levanta Testcontainers (PostgreSQL, MongoDB, Kafka, WireMock) y ejecuta `mvn verify` |
| Quality Gates | `runQualityGates` | Análisis SonarQube: coverage ≥ 80%, debt ratio ≤ 5%, 0 blocker issues |
| Security Scans | `runSecurityScans` | OWASP Dependency-Check + Trivy FS scan sobre dependencias Maven |
| Build & Push Image | `buildAndPushImage` | Docker multi-stage build; push a Gitea Package Registry (local) o OCIR (prod) |
| Scan Image | `scanImage` | Trivy scan sobre la imagen construida; falla si hay CVEs CRITICAL |
| Bump Image Tag | `bumpImageTag` | Actualiza `image.tag` en `values-local.yaml` o `values-prod.yaml` del Helm chart y commit al repo |
| Smoke Tests | `runSmokeTests` | Verifica `/actuator/health/readiness` (HTTP 200, `{"status":"UP"}`) y `/actuator/prometheus` (HTTP 200, contenido Prometheus) |
| Notify | `notify` | Notificación al canal configurado (Slack/Teams/email) con resultado del pipeline |

El pod Jenkins para microservicios backend utiliza `podBackendMaven.yaml` con contenedores: `maven` (maven:3.9-eclipse-temurin-21), `dind` (docker:dind) y `kubectl`.

### Batch Jenkinsfile — Spark / Scala (report-etl-service)

El job ETL no expone endpoints HTTP, por lo que no se ejecutan smoke tests. El pipeline es de CI únicamente:

| Stage | Función Shared Library | Descripción |
|---|---|---|
| Compute Image Tag | `computeImageTag` | Tag basado en git commit hash + build number |
| Build Scala | `buildScalaBatchJob` | `sbt clean assembly`; genera el fat JAR con todas las dependencias Spark |
| Quality Gates | `runQualityGates(projectType:'sbt')` | ScalaFmt check + Scoverage (coverage ≥ 70%); sin SonarQube para Scala |
| Security Scans | `runSecurityScans(projectType:'sbt')` | `sbt dependencyCheck`; Trivy FS scan sobre JARs |
| Build & Push Image | `buildAndPushImage` | Docker multi-stage build desde imagen Spark base; push a registry |
| Scan Image | `scanImage` | Trivy image scan |
| Bump Image Tag | `bumpImageTag` | Actualiza `image.tag` en el CronJob Helm chart |
| Notify | `notify` | Resultado del pipeline |

El pod Jenkins para el ETL utiliza `podScalaBatch.yaml` con contenedores: `sbt` (sbtscala/scala-sbt:eclipse-temurin-21_1.9.x_2.13.x) y `dind`. **No incluye contenedor de integración** (el ETL se prueba con mocks Spark locales via `SparkContext` en modo `local[*]`).

### Frontend Jenkinsfile — Next.js (controlstock-web)

El frontend se despliega como **pod K3s con Traefik Ingress**, no en Vercel ni en ningún servicio de hosting externo. El pipeline incluye pruebas E2E tras el despliegue:

| Stage | Descripción |
|---|---|
| Install | `npm ci` — instalación reproducible de dependencias desde `package-lock.json` |
| Type Check | `npm run type-check` — `tsc --noEmit`; falla si hay errores de tipado TypeScript |
| Lint | `npm run lint` — ESLint con reglas Next.js; falla en warnings de accesibilidad |
| Unit Tests | `npm run test -- --coverage`; cobertura ≥ 70% requerida |
| Build | `npm run build`; verifica que la build de producción Next.js compila sin errores |
| Docker Build | `docker build -t controlstock-web:<tag> .`; imagen multi-stage optimizada |
| Push to Registry | Push a Gitea Package Registry (local) / OCIR (prod) |
| Bump Image Tag | Actualiza `image.tag` en `helm/controlstock-web/values-local.yaml` |
| ArgoCD Sync → K3s | ArgoCD detecta el cambio en el Helm chart y sincroniza el pod en K3s con Traefik Ingress |
| E2E Tests | Playwright ejecuta suite E2E contra el entorno desplegado en K3s; verifica flujos críticos |
| Notify | Resultado del pipeline con enlace a Grafana dashboard del frontend |

---

### Dockerfiles

**Spring Boot — Multi-stage (backend services):**

```dockerfile
# Stage 1: Build
FROM maven:3.9-eclipse-temurin-21 AS builder
WORKDIR /app
COPY pom.xml .
RUN mvn dependency:go-offline -q
COPY src ./src
RUN mvn package -DskipTests -q

# Stage 2: Runtime
FROM eclipse-temurin:21-jre-alpine AS runtime
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
WORKDIR /app
COPY --from=builder /app/target/*.jar app.jar
RUN chown -R appuser:appgroup /app
USER appuser
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "app.jar"]
```

**Spark/Scala — Multi-stage con caché de dependencias sbt:**

```dockerfile
# Stage 1: Dependencias sbt (cacheado)
FROM sbtscala/scala-sbt:eclipse-temurin-21_1.9.9_2.13.12 AS deps
WORKDIR /build
COPY build.sbt .
COPY project ./project
RUN sbt update

# Stage 2: Assembly
FROM deps AS builder
COPY src ./src
RUN sbt assembly

# Stage 3: Spark runtime
FROM apache/spark:3.5.1-scala2.13-java21-python3-ubuntu AS runtime
WORKDIR /opt/spark/work-dir
COPY --from=builder /build/target/scala-2.13/*-assembly.jar app.jar
ENTRYPOINT ["/opt/entrypoint.sh"]
```

---

### Helm Charts

**Microservicios Maven (Spring Boot) → deployment.yaml:**

Genera un manifiesto Kubernetes de tipo `Deployment` + `Service` con:
- `readinessProbe`: `httpGet /actuator/health/readiness` (initialDelaySeconds: 30, periodSeconds: 10)
- `livenessProbe`: `httpGet /actuator/health/liveness` (initialDelaySeconds: 60, periodSeconds: 15)
- `resources.requests`: cpu: 250m, memory: 256Mi
- `resources.limits`: cpu: 1000m, memory: 512Mi
- Variables de entorno inyectadas desde Kubernetes Secrets (generados por Vault Agent Injector)

**ETL Spark/Scala → cronjob.yaml:**

Genera un manifiesto de tipo `CronJob` con:
- `schedule: "0 2 * * *"` (parámetro `--report-schedule`)
- `concurrencyPolicy: Forbid` — no permite ejecuciones solapadas del ETL
- `restartPolicy: Never` — si el Job falla, no se reinicia automáticamente; se requiere intervención manual o reintento del próximo ciclo
- `backoffLimit: 0`
- `activeDeadlineSeconds: 3600` (1 hora máximo de ejecución)

**Valores de entorno por Helm chart:**

Todos los Helm charts generados incluyen:
- `values-local.yaml`: `image.repository: <VPS_IP>:5000/controlstock/<servicio>`, `image.tag: latest`
- `values-prod.yaml`: `image.repository: <ocir-registry>/controlstock/<servicio>`, `image.tag: latest`

El campo `image.tag` es actualizado automáticamente por el paso `bumpImageTag` del pipeline Jenkins en cada build exitoso.

---

## 3. Generación de Changelogs Liquibase

### Automático en scaffold-all-services.sh

Los changelogs Liquibase son generados y publicados en Gitea de forma completamente automática por el script `scaffold-all-services.sh`. Los pasos involucrados son:

#### Step 5 — Changelog inicial por servicio

Para cada microservicio con adaptador PostgreSQL, el script:

1. Localiza el archivo `docs/design/database/SDD-ControlStack-schema.sql`
2. Extrae el bloque DDL correspondiente al bounded context usando la etiqueta `-- BC-XX` como delimitador
3. Convierte el DDL SQL a formato YAML Liquibase usando el conversor interno
4. Escribe el archivo `db/<svc>/changelog/00001_initial_schema.yaml` con un `changeSet` por tabla
5. Genera el `root.yaml` maestro que incluye `00001_initial_schema.yaml`

Cada `changeSet` tiene el formato:
```yaml
- changeSet:
    id: "00001-<tabla>"
    author: scaffold
    changes:
      - createTable:
          tableName: <tabla>
          columns: [...]
```

#### Step 6 — Seed de IAM (iam-service)

Genera el archivo `db/iam-service/changelog/00002_seed_roles.yaml` con los datos maestros del sistema de autorización:

**7 roles del sistema:**
- `Administrador` — acceso total al sistema
- `Supervisor` — supervisión de operaciones e inventario
- `Operador` — operaciones de inventario y ajustes
- `Gerente` — reportes y analítica
- `Analista` — consultas y análisis de datos
- `Auditor` — acceso de solo lectura a logs y auditoría
- `APIConsumer` — acceso programático vía API key para integraciones

**Permisos por módulo** (generados como registros en la tabla `permisos`):

| Módulo | Permisos |
|---|---|
| catalog | `catalog:read`, `catalog:write` |
| inventory | `inventory:read`, `inventory:write` |
| adjustment | `adjustment:read`, `adjustment:write`, `adjustment:approve` |
| alert | `alert:read` |
| supplier | `supplier:read`, `supplier:write` |
| reporting | `reporting:read`, `reporting:generate` |
| audit | `audit:read` |
| integration | `integration:read`, `integration:write` |

**Mappings rol → permisos** (tabla `rol_permisos`): el changelog incluye los `insert` de la tabla de unión para cada combinación rol-permiso según la matriz de autorización definida en el SDD estratégico.

La actualización del `root.yaml` de iam-service incluye el nuevo archivo:
```yaml
databaseChangeLog:
  - include:
      file: 00001_initial_schema.yaml
      relativeToChangelogFile: true
  - include:
      file: 00002_seed_roles.yaml
      relativeToChangelogFile: true
```

#### Step 6b — Repositorio controlstock-migrations en Gitea

1. Crea el repositorio `controlstock-migrations` en la organización `controlstock` de Gitea via API REST
2. Inicializa el repositorio Git local con la estructura `db/<servicio>/changelog/`
3. Realiza commit inicial con mensaje: `feat: initial Liquibase changelogs generated by scaffold`
4. Push a `http://<VPS_IP>:3000/controlstock/controlstock-migrations.git`

**Estructura final del repositorio:**

```
controlstock-migrations/
├── README.md
├── db/
│   ├── iam-service/
│   │   └── changelog/
│   │       ├── root.yaml
│   │       ├── 00001_initial_schema.yaml
│   │       └── 00002_seed_roles.yaml
│   ├── catalog-service/
│   │   └── changelog/
│   │       ├── root.yaml
│   │       └── 00001_initial_schema.yaml
│   ├── inventory-service/
│   │   └── changelog/
│   │       ├── root.yaml
│   │       └── 00001_initial_schema.yaml
│   ├── adjustment-service/
│   │   └── changelog/
│   │       ├── root.yaml
│   │       └── 00001_initial_schema.yaml
│   ├── alert-service/
│   │   └── changelog/
│   │       ├── root.yaml
│   │       └── 00001_initial_schema.yaml
│   ├── supplier-service/
│   │   └── changelog/
│   │       ├── root.yaml
│   │       └── 00001_initial_schema.yaml
│   ├── report-service/
│   │   └── changelog/
│   │       ├── root.yaml
│   │       └── 00001_initial_schema.yaml
│   ├── audit-service/
│   │   └── changelog/
│   │       ├── root.yaml
│   │       └── 00001_initial_schema.yaml
│   └── integration-service/
│       └── changelog/
│           ├── root.yaml
│           └── 00001_initial_schema.yaml
```

---

## 4. Verificación Post-Scaffolding

### Automático en scaffold-all-services.sh

Estos pasos son ejecutados automáticamente por el script como parte de su ejecución completa:

#### Step 9 — compile-services.sh

El script `compile-services.sh` (invocado internamente por el scaffold) encuentra todos los directorios `*-service` en el workspace y ejecuta una compilación Maven sin tests:

```bash
# Ejecutado internamente por scaffold-all-services.sh
for service in $(find . -maxdepth 1 -type d -name '*-service'); do
  echo "Compilando $service..."
  mvn -q -DskipTests package -f "$service/pom.xml"
  if [ $? -ne 0 ]; then
    echo "ERROR: Falló la compilación de $service"
    exit 1
  fi
  echo "✓ $service compilado correctamente"
done
```

Un fallo en la compilación de cualquier servicio detiene el script con exit code 1. El fat JAR generado en `target/` de cada servicio confirma que la estructura Maven es válida.

#### Step 10 — verify-frontend.sh

El script `verify-frontend.sh` (invocado internamente) verifica que el proyecto Next.js generado es válido:

```bash
# Ejecutado internamente por scaffold-all-services.sh
cd frontend/controlstock-web
npm install --prefer-offline
npm run type-check    # tsc --noEmit
npm run lint          # eslint . --ext .ts,.tsx
```

La verificación falla si:
- Hay errores de tipado TypeScript
- Hay warnings de lint en nivel error (configuración `next/core-web-vitals`)
- `npm install` falla por dependencias incompatibles

---

## 5. Configuración Inicial Post-Scaffold

### Automático — Step 11: create-all-secrets-vault.sh

La configuración de secretos en HashiCorp Vault es el **step 11** del script `scaffold-all-services.sh`, ejecutado automáticamente tras la verificación del frontend.

**Funcionamiento del script:**

1. Lee el token root de Vault desde `vault-init.json` (generado por Etapa 0)
2. Para cada servicio, detecta el tipo de base de datos inspeccionando los adaptadores en `infrastructure/driven-adapters/`
3. Aplica el patrón Database-per-Service derivando `controlstock_<svc_slug>` para cada servicio
4. Escribe los secretos en Vault KV v2 bajo la ruta `secret/controlstock/<env>/<service>`

**Secretos escritos por servicio en Vault KV v2:**

```
secret/controlstock/local/<servicio>
├── DB_URL         = jdbc:postgresql://postgresql.data.svc.cluster.local:5432/controlstock_<svc_slug>
├── DB_USER        = controlstock_app
├── DB_PASSWORD    = <contraseña-segura>
├── KAFKA_BOOTSTRAP = kafka.kafka.svc.cluster.local:9092
├── KEYCLOAK_URL   = http://keycloak.auth.svc.cluster.local:8080
├── KEYCLOAK_JWKS_URI = http://keycloak.auth.svc.cluster.local:8080/realms/controlstock/protocol/openid-connect/certs
└── VAULT_ADDR     = http://vault.vault.svc.cluster.local:8200
```

Para servicios con adaptador MongoDB (`catalog-service`, `inventory-service`, `supplier-service`):

```
secret/controlstock/local/<servicio>
└── MONGO_URI = mongodb://controlstock_app:<password>@mongo.data.svc.cluster.local:27017/controlstock_readmodel?authSource=controlstock_readmodel
```

**Comando manual de override** (si se requiere re-ejecutar este paso de forma aislada):

```bash
bash .claude/scripts/create-all-secrets-vault.sh \
  -P controlstock \
  --vm-ip <VPS_IP> \
  --pg-prefix controlstock \
  --mongo-prefix controlstock
```

### Variables de Entorno del Frontend

El step 11 también genera el archivo de configuración local del frontend:

**`frontend/controlstock-web/.env.local`:**

```env
KEYCLOAK_URL=http://<VPS_IP>:8082
KEYCLOAK_REALM=controlstock
NEXT_PUBLIC_API_BASE_URL=http://<VPS_IP>:8000
NEXTAUTH_SECRET=<generado-aleatoriamente>
NEXTAUTH_URL=http://localhost:3000
```

> **Nota:** `.env.local` está en `.gitignore` y nunca se pushea al repositorio. Los valores para producción se inyectan vía variables de entorno del pod K3s a través de Kubernetes Secrets generados desde Vault.

---

## 6. Re-aplicar Infraestructura Terraform

### Steps 12 y 13 — Automáticos

#### Step 12 — terraform apply (actualización de servicios)

Tras generar todos los proyectos, el scaffold actualiza el archivo `terraform/environments/local/local.tfvars` con la lista completa de servicios y ejecuta `terraform apply`:

```hcl
# local.tfvars (actualizado por step 12)
services = [
  "iam-service",
  "catalog-service",
  "inventory-service",
  "adjustment-service",
  "alert-service",
  "supplier-service",
  "report-service",
  "audit-service",
  "integration-service",
  "report-etl-service",
  "controlstock-web"
]
```

El `terraform apply` en este step actualiza:
- Registros en Gitea Package Registry (namespaces de imágenes Docker por servicio)
- Recursos Kubernetes para Vault Agent Injector (ServiceAccounts, roles)
- ArgoCD Applications en el clúster K3s, una por servicio

#### Step 13 — Verificación de Gitea Package Registry y Vault

Al finalizar el `terraform apply`, el script verifica:

1. **Gitea Package Registry:** cada servicio tiene su namespace de imágenes Docker creado en `http://<VPS_IP>:3000/controlstock/<servicio>`
2. **Vault secretos:** `vault kv get secret/controlstock/local/<servicio>` retorna los secretos para cada uno de los 9 microservicios
3. **ArgoCD Applications:** `argocd app list` muestra una Application por servicio en estado `Synced` o `OutOfSync` (pendiente de primer despliegue)

---

## 7. Criterios de Aceptación

### Criterio Principal

- [ ] `scaffold-all-services.sh` con los parámetros completos de la sección 2 **finaliza todos los 13 pasos con exit code 0**

### Repositorios y Código

- [ ] Los 12 repositorios (9 microservicios + ETL + OpenFaaS + frontend) existen en Gitea en `http://<VPS_IP>:3000/controlstock/`
- [ ] Cada repositorio tiene rama `main` con al menos un commit con mensaje `feat: initial scaffold generated`
- [ ] `git clone http://<VPS_IP>:3000/controlstock/iam-service` funciona sin autenticación (repositorio público) o con credenciales del equipo

### Estructura Maven (Microservicios Spring Boot)

- [ ] Cada microservicio tiene estructura hexagonal: `domain/`, `application/`, `infrastructure/driven-adapters/`, `infrastructure/entry-points/`
- [ ] `mvn -DskipTests package` compila exitosamente todos los 9 microservicios
- [ ] Cada `pom.xml` contiene las 5 dependencias de observabilidad (actuator, micrometer-prometheus, micrometer-tracing-bridge-otel, opentelemetry-exporter-otlp, logstash-logback-encoder)

### Estructura Scala/sbt (ETL)

- [ ] `report-etl-service/build.sbt` contiene dependencias de Spark 3.5.1 y Scala 2.13
- [ ] `sbt compile` en `report-etl-service/` compila sin errores

### Frontend Next.js

- [ ] `frontend/controlstock-web/npm run type-check` pasa sin errores TypeScript
- [ ] `frontend/controlstock-web/npm run lint` pasa sin errores ESLint
- [ ] `frontend/controlstock-web/.env.local` existe con `KEYCLOAK_URL`, `KEYCLOAK_REALM` y `NEXT_PUBLIC_API_BASE_URL`

### Changelogs Liquibase

- [ ] Repositorio `controlstock-migrations` accesible en `http://<VPS_IP>:3000/controlstock/controlstock-migrations`
- [ ] Cada servicio tiene `db/<servicio>/changelog/root.yaml` y `db/<servicio>/changelog/00001_initial_schema.yaml`
- [ ] `iam-service` tiene `db/iam-service/changelog/00002_seed_roles.yaml` con los 7 roles del sistema
- [ ] El seed de IAM incluye permisos para los 8 módulos (catalog, inventory, adjustment, alert, supplier, reporting, audit, integration)
- [ ] `run-liquibase-migrations.sh --gitea-clone` aplica todas las migraciones sin errores de checksum ni conflictos

### Vault Secretos

- [ ] `vault kv get secret/controlstock/local/iam-service` retorna secretos con campos `DB_URL`, `DB_USER`, `KAFKA_BOOTSTRAP`, `KEYCLOAK_URL`
- [ ] `vault kv get secret/controlstock/local/inventory-service` incluye campo `MONGO_URI` además de los secretos estándar
- [ ] Los 9 microservicios tienen secretos en Vault bajo `secret/controlstock/local/<servicio>`

### CI/CD y Observabilidad

- [ ] Cada microservicio Spring Boot tiene `Jenkinsfile` con las 10 etapas descritas en la sección 2
- [ ] `report-etl-service` tiene `Jenkinsfile-batch` con las 8 etapas (sin smoke tests)
- [ ] `controlstock-web` tiene `Jenkinsfile-frontend` con etapa E2E post-despliegue
- [ ] Cada `helm/<servicio>/templates/deployment.yaml` contiene las 3 anotaciones Prometheus y el init container `otel-agent`
- [ ] `helm/report-etl-service/templates/cronjob.yaml` tiene `concurrencyPolicy: Forbid` y `restartPolicy: Never`
- [ ] ArgoCD muestra 11 Applications creadas (9 microservicios + ETL + frontend) en el clúster K3s
