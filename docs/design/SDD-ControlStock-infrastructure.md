# Software Design Document — Infraestructura y Gobernanza

**Proyecto:** ControlStock | Parte del conjunto SDD Técnico — etapa Diseño Técnico del SDLC.
Documentos complementarios: `SDD-ControlStock-system.md` · `SDD-ControlStock-design.md`

---

## 1. Infraestructura y Deployment

### Ambientes

| Ambiente | Infraestructura | IP / Hostname | Orquestación |
|---|---|---|---|
| **Development (local)** | VM QEMU/KVM local (4 vCPU / 16 GB RAM) | `localhost` / IP local | K3s single-node |
| **Production** | VPS Oracle Cloud OCI VM.Standard.A1.Flex (4 OCPU / 24 GB, Ampere ARM) | VPS_IP (OCI `sa-saopaulo-1` recomendado) | K3s single-node |

### Infraestructura como Código

La infraestructura completa se aprovisiona con el script:

```
.claude/scripts/base-infrastructure-builder.sh
```

Este script genera en tiempo de ejecución la carpeta `terraform/` completa (providers, variables, main, outputs, módulos y environments), instala K3s via SSH, ejecuta `terraform init → plan → apply` usando el **provider Helm de Terraform** para desplegar todos los servicios en el cluster K3s, y ejecuta tareas post-apply (bases de datos, Gitea, Jenkins Shared Library).

**La carpeta `terraform/` no existe en el repo.** Es generada en runtime. No editarla manualmente; los cambios deben hacerse en el script.

### Módulos Terraform Generados

| Módulo | Helm chart / recurso K8s | Namespace | Puerto NodePort |
|---|---|---|---|
| `modules/namespaces` | `kubernetes_namespace` para todos los namespaces | — | — |
| `modules/helm-infra` | Traefik (ingress), cert-manager | `infra` | 80, 443 |
| `modules/helm-data` | PostgreSQL 16 (Bitnami), MongoDB 7 (Bitnami), Strimzi operator + Kafka CR (KRaft) | `data`, `messaging` | — |
| `modules/helm-identity` | Keycloak 24 (conectado a PostgreSQL) | `identity` | 8082 |
| `modules/helm-secrets` | HashiCorp Vault (standalone + init + unseal + KV v2 `secret/` + política `services-read` + kubernetes auth) | `secrets` | 8200 |
| `modules/helm-cicd` | Gitea (Package Registry OCI), Jenkins, ArgoCD + AppProject + ApplicationSet (Git generator sobre `controlstock-helm-charts`) | `cicd` | 3000, 8080, 8081 |
| `modules/helm-observability` | kube-prometheus-stack (Prometheus + Grafana + AlertManager), Loki, Promtail, Tempo | `observability` | 9090, 3001 |
| `modules/helm-support` | Narayana LRA (`kubernetes_deployment`, namespace `infra`), WireMock (`kubernetes_deployment`, namespace `infra`) | `infra` | 50000 (LRA), 9999 (WireMock) |

**Lo que Terraform gestiona automáticamente sobre Vault:**
- Unseal con clave de `vault-init.json`
- Habilita KV v2 engine en `secret/`
- Crea política `services-read` con acceso de lectura a `secret/data/*/*`
- Habilita kubernetes auth method

**Lo que gestiona el ApplicationSet de ArgoCD:**
- Git generator apunta a `controlstock-helm-charts/charts/*` en Gitea
- Auto-descubre servicios cuando se agregan charts al repo
- Deploya en namespace `apps` con `values-<env>.yaml` por ambiente

### Tabla de Componentes por Módulo

| Decisión de diseño | Módulo Terraform | Namespace K3s |
|---|---|---|
| Kong API Gateway (DS-004) | `modules/helm-infra` (kong chart) | `infra` |
| Keycloak + PostgreSQL IAM (DS-004) | `modules/helm-identity` | `identity` |
| HashiCorp Vault KV v2 (ADR-006) | `modules/helm-secrets` | `secrets` |
| PostgreSQL 16 por servicio (DS-003) | `modules/helm-data` | `data` |
| MongoDB 7 read model (DS-002) | `modules/helm-data` | `data` |
| Kafka Strimzi KRaft (DS-007) | `modules/helm-data` | `messaging` |
| integration-service + Narayana LRA (DS-005, DS-006) | `modules/helm-support` (LRA) + ArgoCD `apps` (integration-service) | `infra` (LRA), `apps` (svc) |
| WireMock (pruebas de integración Camel) | `modules/helm-support` | `infra` |
| Prometheus + Grafana + Loki + Tempo | `modules/helm-observability` | `observability` |
| Jenkins + ArgoCD + Gitea | `modules/helm-cicd` | `cicd` |
| Microservicios de dominio (BC-01 a BC-09) | ArgoCD ApplicationSet | `apps` |
| report-etl-service (CronJob K8s) | ArgoCD ApplicationSet (chart con CronJob) | `apps` |
| report-format-consumer (OpenFaaS) | `modules/helm-support` (openfaas + kafka-connector) + ArgoCD | `openfaas` |

### Registry de Imágenes y CI/CD

- **Dev:** Gitea Package Registry OCI (`http://VPS_IP:3000/controlstock`)
- **Prod:** OCIR Oracle Container Registry
- **Build:** Jenkins pipeline por servicio (Jenkinsfile en cada repo)
- **Deploy:** ArgoCD GitOps — detecta cambio de tag en `values.yaml` del Helm chart y sincroniza automáticamente

### Pipeline CI por Microservicio (Jenkins)

```
checkout → test (Testcontainers) → SonarQube quality gate
→ OWASP Dependency Check → build fat JAR / Scala sbt-assembly
→ Docker build → Trivy image scan (falla ante CVE crítico)
→ push imagen a Gitea Registry → gitleaks → bumpImageTag en helm-charts repo
→ ArgoCD auto-sync
```

---

## 2. Observabilidad y Monitoreo

### Stack de Observabilidad

| Pilar | Herramienta | Descripción |
|---|---|---|
| Métricas | Prometheus + kube-prometheus-stack | Scraping de todos los pods con Micrometer (Spring Boot Actuator). Retención 15 días. |
| Dashboards | Grafana 10.x | Dashboards por servicio: latencia por endpoint, tasa de errores, uso de CPU/memoria, alertas activas del sistema |
| Alertas | Prometheus AlertManager | Alertas ante: latencia p95 > 3 s, tasa de errores 5XX > 1%, pod en CrashLoopBackOff, uso de memoria > 80% |
| Logs | Loki + Promtail | Logs JSON estructurados (Logback). Correlación por `traceId` (OTLP). Retención 30 días. Campos sensibles excluidos por MDC. |
| Trazas distribuidas | Grafana Tempo + OpenTelemetry Java Agent | Trazas distribuidas entre microservicios por `traceId` único. Correlación con logs Loki. Retención 7 días. |

### Instrumentación Mínima Obligatoria por Microservicio

- Latencia por endpoint (histograma p50/p95/p99).
- Tasa de errores por endpoint (contador 4XX / 5XX).
- Eventos Kafka producidos y consumidos por topic.
- Lag de consumidor Kafka por group y topic.
- Tiempo de ejecución del Outbox relay.
- Conexiones activas a PostgreSQL / MongoDB.

### SLIs / SLOs

| SLI | SLO | Alerta |
|---|---|---|
| Latencia consultas (stock, Kardex, dashboard) | p95 < 2 s | AlertManager si p95 > 2 s durante 5 min |
| Latencia escrituras (movimientos) | p95 < 3 s | AlertManager si p95 > 3 s durante 5 min |
| Disponibilidad (uptime) | 99.9% mensual | PagerDuty / notificación si pod down > 30 s |
| Lag de read model MongoDB | < 1 s en operación normal | AlertManager si lag Kafka consumer > 5 s |
| Tasa de errores API | < 0.5% 5XX | AlertManager si tasa 5XX > 1% durante 2 min |

### Health Checks

- **Liveness:** `/actuator/health/liveness` — reinicia el pod si el proceso está bloqueado.
- **Readiness:** `/actuator/health/readiness` — incluye verificación de BD y Kafka; el pod no recibe tráfico hasta estar listo.
- **Startup probe:** tiempo de arranque máximo 60 s para servicios con Vault bootstrap.

---

## 3. Consideraciones No Funcionales

### Escalabilidad

- **Horizontal:** HPA (Horizontal Pod Autoscaler) en K3s para `inventory-service` y `alert-service` (mayor carga previsible). Umbral: CPU > 70% o latencia p95 > 2.5 s.
- **Read model:** MongoDB escala lecturas de forma natural para el ETL y el dashboard.
- **Particionamiento Kafka:** topics `inventory.stock-actualizado` y `inventory.movimientos` con 3 particiones para distribución de carga de alert-service y audit-service.

### Disponibilidad

- **RTO < 30 min:** K3s reinicia pods automáticamente ante fallo. Los scripts de aprovisionamiento reproducen el ambiente completo si el nodo falla (RTO depende del tiempo de bootstrap del script).
- **RPO < 1 hora:** backup diario de PostgreSQL y MongoDB vía `pg_dump` y `mongodump` programados como CronJobs K8s. Archivos en OCI Object Storage.

### Resiliencia

- **Circuit Breaker:** Resilience4j en `integration-service` para cada sistema externo (notificaciones, proveedores REST/FTP). Estado OPEN ante > 50% de fallos en ventana de 10 s.
- **Retry con backoff exponencial:** reintentos en notificaciones fallidas (max 3 intentos; delays 1 s, 4 s, 16 s).
- **Dead Letter Topic:** Kafka DLT para eventos no procesables; monitoreo en Grafana.
- **Transactional Outbox:** garantiza at-least-once en publicación de eventos; sin pérdida de eventos ante fallo del proceso.
- **Idempotencia:** `processed_message` en cada servicio consumidor de Kafka para garantizar procesamiento exactamente-una-vez a nivel de negocio.

### Performance

- **Consultas de Kardex / Dashboard:** servidas desde MongoDB read model (documentos desnormalizados); sin JOINs; latencia p95 < 2 s.
- **Escrituras de stock:** transacciones R2DBC no bloqueantes; stock_levels con optimistic locking (campo `version`).
- **Reportes complejos:** ETL Spark batch; cold start estimado 30-60 s para on-demand; reportes programados sin cold start por schedule.

### Mantenibilidad

- **GitOps:** ArgoCD sincroniza cualquier cambio en `helm-charts` repo automáticamente; no hay despliegues manuales.
- **Migraciones:** Liquibase standalone por servicio; changelogs versionados en `controlstock-migrations` en Gitea.
- **Scaffolding:** el framework SDLC provee scaffolds por tipo de servicio; bootstrapping de un nuevo bounded context en < 30 min.

### Seguridad

Ver sección completa en `SDD-ControlStock-design.md § 4. Diseño de Seguridad Técnica`.

---

## 4. Decisiones Técnicas (ADR)

## ADR-001 — Arquitectura de Microservicios con Diseño Hexagonal y Event-Driven

**Decisión:** Cada bounded context se implementa como un microservicio independiente con arquitectura hexagonal (dominio aislado de infraestructura) y comunicación event-driven mediante Kafka (DS-001).

**Razón:** Modularidad requerida por RNF-008; escalabilidad horizontal independiente por contexto (RNF-003); trazabilidad distribuida (RNF-009). La arquitectura hexagonal garantiza testabilidad del dominio sin infraestructura.

**Tradeoffs:** Mayor complejidad operacional (9+ servicios, CI/CD por servicio, latencia de red inter-servicio) a cambio de despliegue independiente, escala horizontal selectiva y alineación directa con bounded contexts DDD.

**Alternativas consideradas:**
- Modular Monolith: más simple operacionalmente, pero limita escalabilidad horizontal y acopla los contextos en deploy.
- Microservicios sin hexagonal: más rápido de arrancar pero el dominio queda acoplado a la infraestructura (dificulta pruebas y evolución).

---

## ADR-002 — CQRS: PostgreSQL 16 (Command Side) + MongoDB 7 (Read Model)

**Decisión:** Command side en PostgreSQL 16 con transacciones ACID. Read model en MongoDB 7 con proyecciones desnormalizadas por contexto (DS-002, DS-CQRS-1/2/3).

**Razón:** La carga de lectura (Kardex, dashboard, ETL) supera ampliamente la carga de escritura. PostgreSQL garantiza integridad transaccional en escrituras de stock; MongoDB responde consultas de Kardex sin JOINs costosos (SLA p95 < 2 s, RNF-002).

**Tradeoffs:** Consistencia eventual entre command side y read model (lag < 1 s normal); complejidad de sincronización (Outbox → Kafka → projection consumer → MongoDB); el Kardex visible en dashboard puede tener un margen respecto al stock operacional.

**Alternativas consideradas:**
- Una sola BD PostgreSQL: más simple pero degrada rendimiento de lectura bajo carga.
- ElasticSearch como read model: mayor complejidad operacional sin beneficio suficiente para los volúmenes estimados.

---

## ADR-003 — Database-per-Service con Liquibase Standalone

**Decisión:** Cada microservicio posee y gestiona su propia base de datos aislada (`controlstock_<svc_slug>`). Ningún otro servicio accede directamente a ella (ni lectura ni escritura). Las BDs se provisionan por `init-databases.sh`; el esquema lo aplica **Liquibase standalone** (`run-liquibase-migrations.sh --gitea-clone`) como paso previo al despliegue, con changelogs en el repo `controlstock-migrations` en Gitea. No se usa Flyway (incompatible con R2DBC reactivo). La comunicación entre servicios usa eventos Kafka o REST, nunca acceso directo a la BD ajena (DS-003).

**Razón:** Autonomía de esquema e independencia de despliegue por servicio. Sin Database-per-Service, los microservicios se acoplan implícitamente a través del esquema de BD compartida.

**Tradeoffs:** Autonomía e independencia de despliegue a cambio de consistencia eventual y ausencia de JOINs entre BDs operacionales. Datos compartidos requieren eventos o REST.

**Alternativas consideradas:**
- BD compartida: elimina la complejidad de consistencia eventual pero acopla los servicios al esquema compartido.
- Flyway: incompatible con R2DBC (requiere conexiones JDBC bloqueantes); descartado.

---

## ADR-004 — Autenticación y Autorización Centralizada: Keycloak + Kong

**Decisión:** Keycloak 24 (realm `controlstock`) como Identity Provider OIDC/OAuth 2.0. Kong API Gateway valida JWT RS256 en todas las peticiones externas antes de enrutar a los microservicios. Los microservicios confían en los claims pre-validados del JWT (DS-004).

**Razón:** Centralizar la validación JWT en Kong elimina la replicación de lógica de autenticación en cada microservicio. Los endpoints internos (K3s service-to-service DNS) no pasan por Kong.

**Tradeoffs:** Dependencia de Kong como punto crítico de entrada (mitigada con HPA); el caché de claves públicas introduce un lag de revocación máximo configurable (5 min recomendado).

**Alternativas consideradas:**
- Validación JWT en cada microservicio: duplica código y configuración; descartado.
- Spring Security OAuth Resource Server: complementario en capa de aplicación, no sustituto de Kong.

---

## ADR-005 — Apache Camel 4.10.2 como Capa de Integración en `integration-service`

**Decisión:** Centralizar toda la conectividad con sistemas externos en `integration-service` con Apache Camel 4.10.2. Bridge reactivo Camel↔Reactor vía `camel-reactive-streams`; prohibido `block()`. Resilience4j (circuit breaker, retry, bulkhead) por sistema externo. ACL por proveedor (traducción de modelos externos al lenguaje ubicuo). Solo `integration-service` se comunica con sistemas externos (DS-005).

**Razón:** Gobierno central de credenciales (Vault), SLAs, reintentos y circuit breakers. Aísla el dominio de la volatilidad de contratos externos. Camel EIP gestiona protocolos heterogéneos (HTTP, FTP/SFTP) de forma homogénea.

**Tradeoffs:** `integration-service` es un componente crítico de alta disponibilidad (cuello de botella potencial); su fallo bloquea notificaciones externas y reposición de inventario. Mitigado con HPA y circuit breaker.

**Alternativas consideradas:**
- Integración directa desde cada microservicio: duplica ACL y manejo de errores; descartado.
- Spring WebClient directo: sin EIP, gestión de protocolos heterogéneos más compleja.

---

## ADR-006 — Orquestación de Saga con Narayana LRA (Camel Saga EIP)

**Decisión:** Saga con estilo de orquestación. Orquestador en `integration-service` (Camel Saga EIP + coordinador Narayana LRA en namespace `infra`). Compensaciones idempotentes via endpoints `POST /{recurso}/{id}/compensar` + tabla `processed_message` en cada participante. Persistencia del estado de saga en `saga_instance` y `saga_step_log` en `controlstock_integration` (DS-006).

**Razón:** La orquestación centraliza visibilidad y control del flujo transaccional; facilita debugging de compensaciones y monitoreo de sagas en curso. `integration-service` ya es el ACL externo y el punto de coordinación natural para flujos que involucran sistemas externos (Saga-01).

**Tradeoffs:** `integration-service` es un punto único de fallo para los flujos de saga; mayor acoplamiento al orquestador. A cambio de control centralizado y visibilidad explícita del estado de la saga.

**Alternativas consideradas:**
- Coreografía (eventos puro): mayor autonomía pero visibilidad limitada del flujo; debugging complejo.
- Saga orquestada con orquestador dedicado independiente: mayor operacional sin beneficio adicional para este volumen.

---

## ADR-007 — Transactional Outbox Pattern para Publicación de Eventos

**Decisión:** Cada microservicio escribe el evento en una tabla `outbox` de su BD PostgreSQL dentro de la misma transacción de negocio. Un proceso Outbox Relay (scheduled R2DBC, compatible con stack reactivo) lee de `outbox` con status='PENDING' y publica en Kafka. Relay publica en orden de `created_at`; reintentos ante fallo de publicación; DLT para eventos no procesables (DS-007).

**Razón:** Garantiza at-least-once: si la transacción de negocio falla, el evento nunca se escribe en outbox; si la publicación a Kafka falla, el relay reintenta. Elimina el riesgo de eventos perdidos o publicados sin la transacción correspondiente. Compatible con R2DBC reactivo (sin coordinación de transacciones XA).

**Tradeoffs:** Latencia adicional mínima entre la escritura en PostgreSQL y la publicación en Kafka (proporcional al intervalo del relay scheduled). El read model MongoDB tiene consistencia eventual.

**Alternativas consideradas:**
- Publicación directa a Kafka en la transacción: incompatible con R2DBC (sin soporte XA); riesgo de eventos publicados sin transacción confirmada.
- Debezium CDC: mayor consistencia a cambio de mayor complejidad operacional; viable para evolución futura.

---

## ADR-008 — ETL Spark Unificado como Kubernetes CronJob

**Decisión:** Un único job Spark (`report-etl-service`, Scala 2.13 + Apache Spark 3.5.1) realiza extracción desde MongoDB (y `controlstock_audit` vía JDBC), validación con patrón Factory por `ReportType` y generación de .parquet en MinIO. Desplegado como **CronJob K8s** (schedule configurable via `--schedule` flag en el script); ArgoCD sincroniza el CronJob. Jenkins termina en `bumpImageTag` sin smoke tests HTTP. Para solicitudes on-demand, el job se dispara consumiendo el topic Kafka de solicitud (DS-008).

**Razón:** Un ETL unificado elimina duplicación de lógica de extracción. El patrón Factory por `ReportType` centraliza la transformación. CronJob K8s elimina el overhead de servidor persistente para reportes periódicos.

**Tradeoffs:** Cold start del job Spark en on-demand (estimado 30-60 s en K3s); latencia de reporte aceptable según SLA (≤ 10 s para reportes complejos corresponde al reporte pre-generado; on-demand justifica el cold start). Simplicidad operacional a cambio de latencia.

**Alternativas consideradas:**
- Servicio REST persistente de reportería: overhead continuo de recursos sin justificación para el volumen estimado.
- Streaming en tiempo real: sobre-ingeniería para el volumen actual (~50 K filas/mes).

---

## ADR-009 — Función OpenFaaS para Conversión de Formatos de Reporte

**Decisión:** Función OpenFaaS (`report-format-consumer`, python3-http) desplegada via Helm (`openfaas/openfaas` + `openfaas/kafka-connector`) en K3s (dev y prod sobre VPS). Sin EventBridge intermedio. Almacenamiento en MinIO (K3s dev) o OCI Object Storage/S3-compatible (prod). El formato se determina del campo `formatoDestino` del evento `ReporteParquetGenerado` (DS-009).

**Razón:** OpenFaaS es la plataforma serverless ya aprovisionada en el stack. El modelo event-driven elimina el servidor persistente para conversión de archivos. Escala a cero en reposo.

**Tradeoffs:** Posible cold start de la función en períodos de inactividad; dependencia del Kafka Connector de OpenFaaS; depuración más compleja en entorno serverless.

**Alternativas consideradas:**
- Microservicio REST dedicado de formatos: overhead de servidor persistente para una operación event-driven ocasional.
- Lambda / Cloud Functions: vendor lock-in incompatible con la restricción de stack open-source (ADC).

---

## 5. Riesgos Técnicos

| ID | Riesgo | Impacto | Probabilidad | Mitigación |
|---|---|---|---|---|
| RT-001 | Alta complejidad operacional de 9+ microservicios para un equipo de tamaño aún no definido | Alto | Media | Scaffolds del framework SDLC reducen fricción de bootstrapping; ArgoCD GitOps simplifica despliegue declarativo; documentación técnica completa en este SDD |
| RT-002 | Consistencia eventual del read model MongoDB genera lecturas desactualizadas en dashboard o Kardex | Medio | Media | UI indica timestamp de última actualización del read model; monitoreo de lag Kafka (SLA < 1 s); alertas si lag > 5 s |
| RT-003 | Curva de aprendizaje de Scala + Apache Spark para el ETL de reportería | Medio | Media | Scaffold `scala_hexagonal_scaffold.py` provisto; Testcontainers para pruebas ETL; asignar perfil con experiencia JVM/Scala |
| RT-004 | SLA del servicio externo de notificaciones (tercero) no garantizado; fallo bloquea alertas externas | Alto | Media | Diseño desacoplado: alertas registradas en BD independientemente del envío externo; Circuit Breaker Resilience4j; reintentos con backoff exponencial (3 intentos) |
| RT-005 | Recursos del VPS OCI A1.Flex (4 OCPU / 24 GB) insuficientes bajo picos de carga estacional | Alto | Media | HPA para inventory-service y alert-service; monitoreo Grafana con alertas de CPU/memoria > 80%; evaluación de upgrade de shape OCI si métricas lo justifican |
| RT-006 | Dependencias entre bounded contexts en sagas aumentan complejidad de pruebas de integración | Medio | Media | WireMock (NodePort 9999) para mocking de proveedores externos; Testcontainers para PostgreSQL/MongoDB/Kafka en tests de integración; cobertura ATDD/BDD como criterio de DoD |
| RT-007 | Cold start de Narayana LRA Coordinator o report-etl-service introduce latencia inesperada | Medio | Baja | Readiness probe configurado; pod pre-calentado con tráfico mínimo; monitoreo de latencia de arranque en Grafana |
| RT-008 | Normativa local de protección de datos no verificada antes del go-live | Alto | Baja | Revisión legal pendiente (ADC sección 7); prácticas actuales (Vault, RBAC, TLS, auditoría) alinean con ISO 27001; bloquear go-live hasta confirmación |

---

## 6. Recomendación y Próximos Pasos

### Estado del Diseño Técnico

El diseño técnico está completo y listo para iniciar la etapa de Implementación. Los tres documentos SDD técnicos (system, design, infrastructure) junto con los artefactos de soporte (C4 diagrams, OpenAPI spec, SQL schema, MongoDB collections) proveen la base de referencia completa para el equipo de desarrollo.

### Preparación para Implementación

- Las decisiones estratégicas (DS-001 a DS-010) están formalizadas como ADRs técnicos.
- Los contratos de API están definidos en la especificación OpenAPI 3.0.3.
- Los esquemas de BD están documentados como DDL (PostgreSQL) y colecciones (MongoDB).
- La matriz de trazabilidad AC → Prueba técnica permite mapear cada criterio ATDD a su prueba ejecutable en CI/CD.
- Los flujos de saga están documentados con pasos, compensaciones e idempotencia.

### Áreas que Requieren Validación Adicional

1. **Tamaño y perfiles del equipo:** impacta la planificación de sprints y la viabilidad de desarrollar 9+ microservicios en paralelo.
2. **Región OCI confirmada:** `sa-saopaulo-1` recomendada; confirmar antes de configurar OCIR y OCI Object Storage.
3. **Revisión legal de protección de datos:** bloqueador de go-live; coordinar con área legal antes de habilitar el acceso a datos de auditoría en producción.
4. **Período de retención del Kardex:** confirmar con área legal/contable (mínimo 5 años estimado) para definir estrategia de archivado.
5. **Estrategia de migración de datos iniciales:** script de carga desde hojas de cálculo existentes (catálogo + stock de apertura).

### Dependencias y Bloqueadores

| Ítem | Tipo | Estado |
|---|---|---|
| Tamaño y perfiles del equipo de desarrollo | Organizacional | Por definir |
| Región OCI confirmada | Técnico-organizacional | Por definir (sa-saopaulo-1 recomendado) |
| Revisión legal de normativas de datos | Regulatoria | Pendiente — bloqueador de go-live |
| Período de retención de Kardex | Legal/contable | Pendiente |
| Disponibilidad del entorno de desarrollo (VM QEMU/KVM) | Infraestructura | Pendiente confirmación TI |

### Próxima Etapa del SDLC

**Desarrollo / Implementación.** Los documentos de esta etapa son entrada para los planes de desarrollo por microservicio y para la configuración del pipeline CI/CD.

### Secuencia Completa de Scripts de Aprovisionamiento

```bash
# 1. Infraestructura base: K3s + Terraform + Helm
#    Genera terraform/, instala K3s, despliega todos los servicios en K3s
.claude/scripts/base-infrastructure-builder.sh \
  --vm-ip <VPS_IP> --project controlstock \
  --pg-prefix controlstock --mongo-prefix controlstock \
  --services "iam-service,catalog-service,inventory-service,adjustment-service,alert-service,supplier-service,report-service,audit-service,integration-service" \
  --env local

# Módulos opcionales (incluidos por defecto para ControlStock):
# --no-lra    → deshabilitar Narayana LRA (NO recomendado: Saga-01 y Saga-02 lo requieren)
# --no-wiremock → deshabilitar WireMock (deshabilitar solo en prod)

# 2. Secrets por microservicio en HashiCorp Vault
.claude/scripts/create-all-secrets-vault.sh \
  -P controlstock --vm-ip <VPS_IP> \
  --pg-prefix controlstock --mongo-prefix controlstock

# 3. Migraciones Liquibase por servicio (repetir por cada servicio)
.claude/scripts/run-liquibase-migrations.sh \
  --vm-ip <VPS_IP> --project controlstock \
  --service iam-service --pg-prefix controlstock --gitea-clone
# ... repetir para catalog-service, inventory-service, adjustment-service,
#     alert-service, supplier-service, report-service, audit-service, integration-service

# 4. Configurar CI/CD: Jenkins jobs + Gitea webhooks + ArgoCD credentials
.claude/scripts/setup-cicd-pipeline.sh \
  -P controlstock \
  -S "iam-service,catalog-service,inventory-service,adjustment-service,alert-service,supplier-service,report-service,audit-service,integration-service" \
  --vm-ip <VPS_IP> --env local

# 5. Verificar el ambiente completo (health checks + tabla de endpoints)
.claude/scripts/init-dev-environment.sh \
  -P controlstock --vm-ip <VPS_IP>
```

Los módulos opcionales de `base-infrastructure-builder.sh` se controlan con `--no-lra`, `--no-wiremock`, `--no-loki`, `--no-tempo`.
