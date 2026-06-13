# Architectural Decision Context (ADC)
# ControlStock

**Proyecto:** ControlStock  
**Versión del ADC:** 1.0  
**Fecha:** 2026-06-12  
**Autor(es):** AndersonElit

---

## 1. Identificación

- **Proyecto:** ControlStock
- **Versión del ADC:** 1.0
- **Fecha:** 2026-06-12
- **Autor(es):** AndersonElit

---

## 2. Contexto Tecnológico *

### Stack permitido / mandatorio

| Capa | Tecnología / Herramienta | Estado | Justificación |
|------|--------------------------|--------|---------------|
| Lenguaje backend | Java 21 + Spring Boot 3.4.x (WebFlux reactivo) | Mandatorio | Definido en `maven_hexagonal_scaffold.py`; soporte LTS, ecosistema Spring maduro, WebFlux para alta concurrencia reactiva |
| Lenguaje frontend | TypeScript + Next.js 15 + React 19 | Mandatorio | Definido en `nextjs_feature_scaffold.py`; SSR, arquitectura Feature-Based enterprise, type-safety |
| Lenguaje batch/reportería | Scala 2.13 + Apache Spark 3.x | Mandatorio | Definido en `scala_hexagonal_scaffold.py`; ETL distribuido para transformación de reportes a partir del read model |
| Lenguaje integración | Java 21 + Apache Camel 4.10.2 + Spring WebFlux | Mandatorio | Definido en `integration_service_scaffold.py`; capa ACL con EIP para integración con proveedores externos |
| Base de datos relacional | PostgreSQL 16 | Mandatorio | Definido en `base-infrastructure-builder.sh` (Helm Bitnami); BD de escritura (command side CQRS), migraciones con Liquibase |
| Base de datos no relacional | MongoDB 7 | Mandatorio | Definido en `base-infrastructure-builder.sh` (Helm Bitnami); BD de lectura (read model CQRS), dashboards y Kardex |
| Mensajería / eventos | Apache Kafka 3.8 (Strimzi Operator en K3s) | Mandatorio | Definido en `base-infrastructure-builder.sh`; bus de eventos entre microservicios, Transactional Outbox relay |
| Autenticación / identidad | Keycloak (Helm Bitnami) + Kong Gateway (JWT plugin) | Mandatorio | Definido en `base-infrastructure-builder.sh`; OIDC/OAuth 2.0 + JWT RS256 validado por Kong en el ingreso de todas las peticiones |
| API Gateway | Kong (Helm konghq.com) | Mandatorio | Definido en `base-infrastructure-builder.sh`; JWT, rate-limiting y CORS global; registro de rutas vía Kong Ingress Controller |
| Ingress frontend | Traefik (Helm traefik.io) | Mandatorio | Definido en `base-infrastructure-builder.sh`; ingress del pod Next.js en K3s |
| Gestión de secretos | HashiCorp Vault 0.28 (Helm) con KV v2 | Mandatorio | Definido en `base-infrastructure-builder.sh`; todos los microservicios leen secrets vía `spring-cloud-vault-config` |
| Monitoreo / observabilidad | Prometheus + Grafana (kube-prometheus-stack) + Loki + Promtail + Grafana Tempo (OTLP) + OpenTelemetry Java Agent | Mandatorio | Definido en `base-infrastructure-builder.sh` módulo `helm-observability`; métricas, logs estructurados JSON y trazas distribuidas |
| CI/CD | Jenkins (CI) + ArgoCD (CD/GitOps) + Gitea (SCM + Package Registry) | Mandatorio | Definido en `base-infrastructure-builder.sh` módulo `helm-cicd`; `Jenkinsfile` generado por scaffolds; ApplicationSet Git generator de ArgoCD |
| Build tool backend | Maven 3.9 + Eclipse Temurin 21 Alpine (imagen builder) | Mandatorio | Definido en `maven_hexagonal_scaffold.py` Dockerfile |
| Build tool frontend | Node.js 20 Alpine + npm | Mandatorio | Definido en `nextjs_feature_scaffold.py` Dockerfile |
| Contenedores | Docker (imagen multi-stage) + Kaniko (build en K3s sin Docker daemon) | Mandatorio | Definido en Jenkinsfiles de los scaffolds |
| Orquestación | K3s v1.31.4 (nativo en VPS) | Mandatorio | Definido en `base-infrastructure-builder.sh` y `qemu-vps.sh` |
| Infraestructura como código | Terraform ≥ 1.7 (Helm + Kubernetes providers) | Mandatorio | Definido en `base-infrastructure-builder.sh`; gestiona todos los recursos del cluster |
| Almacenamiento de objetos | MinIO (S3-compatible, Helm Bitnami) | Mandatorio | Definido en `base-infrastructure-builder.sh`; bucket `controlstock-reports` para reportes Parquet, XLS, CSV |
| Serverless / formatos | OpenFaaS (Helm faas-netes) + Kafka Connector | Mandatorio | Definido en `report_lambdas_scaffold.py`; capa de generación de formatos (XLS, CSV) disparada desde Kafka |
| Migraciones BD | Liquibase (standalone, no en classpath del JAR) | Mandatorio | Definido en `maven_hexagonal_scaffold.py`; compatible con R2DBC reactivo; ejecutado pre-deploy vía `run-liquibase-migrations.sh` |
| Pruebas contrato | WireMock 3.x | Mandatorio | Definido en `base-infrastructure-builder.sh`; mock de proveedores externos en pruebas de integración del `integration-service` |
| Pruebas integración backend | Testcontainers | Mandatorio | Definido en Jenkinsfile del scaffold; levanta PostgreSQL/MongoDB/Kafka en Docker para tests de integración |
| Pruebas E2E frontend | Playwright | Mandatorio | Definido en `nextjs_feature_scaffold.py` package.json |
| Calidad de código | SonarQube | Mandatorio | Referenciado en Jenkinsfile; quality gate requerido antes de push de imagen |
| Seguridad imagen/deps | Trivy (image scan) + OWASP Dependency Check + gitleaks | Mandatorio | Referenciados en Jenkinsfile; pipeline falla ante CVE crítico |
| Coordinador de transacciones | Narayana LRA (coordinator quay.io) | Mandatorio | Definido en `base-infrastructure-builder.sh` módulo `helm-support`; saga LRA para flujos transaccionales entre microservicios |

### Stack excluido

| Tecnología | Motivo de exclusión |
|------------|---------------------|
| Aplicaciones móviles nativas (iOS / Android) | Fuera del alcance explícito del SRS v1.0 |
| Facturación electrónica / ERP / CRM | Fuera del alcance explícito del SRS v1.0 |
| Plataformas e-commerce | Fuera del alcance explícito del SRS v1.0 |
| Vercel / Netlify (despliegue frontend) | El frontend se despliega como pod K3s con Traefik Ingress; no se usa ningún proveedor PaaS externo |
| Flyway (migraciones BD) | Incompatible con R2DBC reactivo (requiere JDBC bloqueante); reemplazado por Liquibase standalone |
| Docker Compose (orquestación) | Sustituido por K3s nativo en VPS en ambos entornos |
| AWS Lambda / Azure Functions (serverless) | La capa serverless se implementa con OpenFaaS en K3s; no se usan funciones de cloud público |
| RabbitMQ | La mensajería está estandarizada en Kafka con Strimzi; RabbitMQ no está aprovisionado en el cluster |

---

## 3. Infraestructura y Despliegue *

> **Decisión de infraestructura por defecto (framework SDLC):**
> - **Entorno local / dev:** VM QEMU/KVM creada con `.claude/scripts/qemu-vps.sh`, Ubuntu, SSH key-only, UFW, UTC, NTP. K3s, PostgreSQL 16, MongoDB 7, Kafka, Keycloak, Vault y herramientas CI/CD corren como releases Helm gestionados por Terraform en la VM.
> - **Producción:** VPS en Oracle Cloud Infrastructure (OCI) — misma imagen Ubuntu, misma configuración Terraform/Helm. OCIR como registry de imágenes de producción.

- **Modelo de despliegue:** VPS-nativo (local + cloud)
- **Cloud provider:** Oracle Cloud Infrastructure (OCI)
- **Región OCI / residencia de datos:** por definir (recomendado: sa-saopaulo-1 por proximidad a usuarios finales en LATAM)
- **Shape OCI producción:** VM.Standard.A1.Flex 4 OCPU 24 GB (Ampere ARM — Always Free eligible o tier pago según crecimiento)
- **Modelo de servicio:** SaaS / on-premise instalable (web responsive; acceso por navegador)
- **Entornos requeridos:** `dev = VM QEMU/KVM local`, `prod = VPS Oracle Cloud OCI` (agregar `staging` en año 1 si el equipo lo requiere)
- **Estrategia de contenedores:** K3s nativo en VPS en ambos entornos; pods gestionados por ArgoCD ApplicationSet (Git generator)
- **Registry de imágenes:** Gitea Package Registry en VM local (dev) / OCIR en Oracle Cloud (prod)
- **Base de datos:** PostgreSQL 16 y MongoDB 7 como releases Helm (Bitnami) en namespace `data` del cluster K3s, en ambos entornos
- **Identidad / autenticación:** Keycloak en K3s (namespace `identity`), realm `controlstock`; Kong Gateway valida JWT RS256 en todas las peticiones entrantes
- **Secretos:** HashiCorp Vault en K3s (namespace `secrets`), KV v2 path `controlstock/<env>/<servicio>`; todos los microservicios consumen secrets en runtime vía `spring-cloud-vault-config`

---

## 4. Estilo Arquitectónico Preferido *

- **Estilo principal:** Microservicios con arquitectura hexagonal (DDD) + Event-Driven
- **Justificación:** El SRS requiere modularidad (RNF-008), escalabilidad horizontal (RNF-003), trazabilidad distribuida (RNF-009) y extensibilidad de integraciones externas (RF-018, RF-019). La arquitectura hexagonal garantiza separación clara entre dominio, aplicación e infraestructura. Los microservicios permiten escalar de forma independiente los componentes de mayor carga (movimientos de inventario, alertas). Kafka desacopla el motor de alertas del registro de movimientos.
- **Patrón de integración entre componentes:** REST (síncrono, interno vía Kong) + Mensajería asíncrona Kafka (eventos de dominio y outbox relay)
- **Patrón de acceso a datos:** CQRS
- **CQRS — BD de escritura (command):** PostgreSQL 16 (datos normalizados, transacciones ACID, Liquibase migrations)
- **CQRS — BD de lectura (query / read model):** MongoDB 7 (documentos desnormalizados, proyecciones de Kardex, dashboard KPIs, datos para reportería)
- **CQRS — Sincronización:** Transactional Outbox (tabla `outbox` en PostgreSQL) → Outbox Relay (scheduled) → Kafka topic → consumidor que materializa el read model en MongoDB

---

## 5. Atributos de Calidad y SLAs *

| Atributo | Meta | Prioridad |
|----------|------|-----------|
| Disponibilidad | 99.9% medido mensualmente en producción (RNF-001) | Alta |
| Latencia máxima (p95) | < 2 s para consultas de stock y Kardex (RNF-002) | Alta |
| Latencia operaciones escritura | < 3 s para registro de movimientos (RNF-002) | Alta |
| Throughput esperado | Soporte a 500 usuarios concurrentes sin degradación (RNF-003) | Alta |
| Usuarios concurrentes pico | 500 usuarios simultáneos | Alta |
| Generación de reportes | ≤ 10 s para reportes complejos (RNF-002) | Media |
| RTO (Recovery Time Objective) | < 30 minutos (estimado; mantenimientos fuera de horario operativo con 48h de aviso — RNF-001) | Alta |
| RPO (Recovery Point Objective) | < 1 hora (estimado; respaldo diario de PostgreSQL y MongoDB) | Alta |
| Tiempo de build/deploy máximo | < 30 minutos por microservicio (pipeline Jenkins completo) | Media |

---

## 6. Escala y Crecimiento

- **Usuarios activos esperados — lanzamiento:** 20–50 usuarios (operadores, supervisores, administrador, gerentes de la organización)
- **Usuarios activos esperados — año 1:** 100–200 usuarios
- **Usuarios activos esperados — año 3:** 300–500 usuarios (posible expansión a múltiples sucursales)
- **Volumen de datos estimado — año 1:** ~500 K movimientos de inventario (Kardex), ~10 K productos activos, < 50 GB total entre PostgreSQL y MongoDB
- **Pico de carga estacional o eventos especiales:** cierres de inventario mensual/trimestral (concentración de ajustes y reportes); posible pico de fin de año
- **¿Es un MVP o sistema de producción a escala?** Sistema de producción a escala completa desde el inicio; el MVP está acotado por el alcance del SRS v1.0 (sin mobile, sin ERP, sin e-commerce)

---

## 7. Compliance y Regulaciones *

| Regulación / Estándar | Aplicable | Notas |
|-----------------------|-----------|-------|
| GDPR | No | Los datos gestionados son de inventario y proveedores (personas jurídicas); no se procesan datos personales de usuarios finales en escala regulada |
| HIPAA | No | Dominio de Retail / Inventario; no aplica |
| PCI-DSS | No | El sistema no procesa, almacena ni transmite datos de tarjetas de pago |
| SOC 2 | Por verificar | No mandatorio en v1.0; evaluar si la organización tiene clientes enterprise que lo exijan |
| ISO 27001 | Por verificar | Recomendable a mediano plazo; las prácticas de seguridad implementadas (Vault, RBAC, TLS, auditoría inmutable) alinean con sus controles |
| Normativas locales de protección de datos | Por verificar | Depende del país de operación; revisar con equipo legal antes del go-live |

- **Requisitos de retención de datos:** El registro de auditoría (RF-017) es inmutable e indefinido. Los movimientos de inventario (Kardex) se retienen por el período fiscal aplicable (mínimo 5 años, a confirmar con el área legal/contable).
- **Requisitos de auditoría obligatoria:** Toda operación de creación, modificación e inactivación queda registrada de forma automática e inmutable (RF-017, RN-011). El log de auditoría incluye usuario, timestamp, entidad y valores antes/después.
- **Restricciones de exportación de datos:** Los datos de inventario no tienen restricciones de exportación conocidas en v1.0. Los reportes exportables (PDF/XLSX) deben restringirse a usuarios con permiso explícito (RN-009).

---

## 8. Integraciones y Sistemas Existentes

### Sistemas legados

| Sistema | Tipo | Forma de integración | Estado |
|---------|------|----------------------|--------|
| Hojas de cálculo / sistemas dispersos de inventario | Archivos (Excel/CSV) | Migración one-time vía script de carga inicial | Reemplazar |

### APIs y servicios de terceros ya definidos

| Servicio / Sistema externo | Proveedor | Propósito | Protocolo | Dirección | SLA / Latencia | Criticidad |
|----------|-----------|-----------|-----------|-----------|----------------|------------|
| Servicio de notificaciones (email/mensajería) | Por definir (ej. SMTP relay, SendGrid, Twilio) | Envío de alertas automáticas de stock bajo/sobre y notificaciones de ajustes (RF-018) | REST / SMTP | Saliente (consumo) | p95 < 5 s / 99% | Alta |
| Proveedores externos de inventario | Múltiples (por proveedor) | Consulta de disponibilidad y envío de solicitudes de reposición (RF-019) | REST / archivo (FTP/SFTP según capacidad del proveedor) | Saliente (consumo) | por definir por proveedor | Media |
| Sistema Externo (API) — consumidores de la API pública | Terceros integradores | Consulta de stock, registro de movimientos y obtención del Kardex (RF-020) | REST | Entrante | p95 < 2 s | Alta |

### Dependencias de datos

- **Fuentes de datos externas:** APIs REST y/o archivos de proveedores externos (disponibilidad de productos); servicio de notificaciones externo (confirmación de entrega de alertas).
- **Sistemas que consumen datos de este sistema:** Sistemas externos integrados vía API REST pública (RF-020); herramientas de BI externas que consuman los reportes exportados (PDF/XLSX).

### Capa de integración (Apache Camel)

- **¿Centralizar la conectividad con sistemas externos en un microservicio dedicado `integration-service` (capa de integración / ACL con Apache Camel)?** Sí
- **Justificación:** El SRS requiere integración con múltiples proveedores externos con protocolos heterogéneos (REST y archivo — RF-019) y con un servicio de notificaciones externo (RF-018). Centralizar en `integration-service` con Apache Camel 4.10.2 garantiza gobierno central de credenciales, SLAs, manejo de reintentos (RNF-001) y aísla el dominio de negocio de las particularidades de integración. El `integration-service` actúa también como orquestador de saga.
- **Protocolos de entrada no-HTTP a soportar:** `file` (FTP/SFTP para proveedores sin capacidad API REST), `timer` (polling periódico de disponibilidad); Camel EIP gestiona ambos.

### Estrategia de transacciones distribuidas (Saga)

- **¿Hay transacciones que cruzan servicios?** Sí — el flujo de reposición de stock (integración con proveedor → creación de entrada de inventario → actualización de stock → evaluación de alertas) abarca múltiples servicios.
- **Estilo de saga preferido:** Orquestación
- **Ubicación del orquestador:** `integration-service` (Camel Saga EIP + Narayana LRA)
- **Coordinador de transacciones:** Narayana LRA (Long Running Actions) — desplegado en K3s (namespace `infra`, puerto 50000), definido en `base-infrastructure-builder.sh`

| Flujo transaccional | Servicios participantes | Paso(s) que requieren compensación | Criticidad |
|---------------------|-------------------------|-------------------------------------|------------|
| Reposición de inventario vía proveedor externo | `integration-service` → `inventory-service` → `alert-service` | Reversa de entrada de inventario si la confirmación del proveedor falla o el stock supera el máximo y la alerta no puede enviarse | Alta |
| Registro de ajuste con aprobación | `adjustment-service` → `inventory-service` → `kardex-service` | Reversa del impacto al stock si la actualización del Kardex falla | Media |

---

## 9. Equipo y Capacidad

- **Tamaño del equipo de desarrollo:** por definir (proyecto en etapa de planeación; el SRS asume designación de PM antes del inicio formal)
- **Perfil dominante:** por definir
- **Experiencia con el estilo arquitectónico elegido:** por definir (el framework SDLC con scaffolds reduce la curva de aprendizaje en microservicios hexagonales)
- **Velocidad de entrega esperada:** sprints de 2 semanas; cadencia de features por sprint a definir en la etapa de planeación detallada
- **¿Hay equipos externos / outsourcing?** por definir

---

## 10. Presupuesto de Infraestructura

- **Presupuesto mensual de infraestructura (cloud/servidores):** por definir (OCI VM.Standard.A1.Flex 4 OCPU / 24 GB tiene elegibilidad Always Free en la capa OCI; costos adicionales por storage, transferencia y OCIR a confirmar)
- **¿Existe presupuesto para licencias de software comercial?** No requerido — todo el stack es open-source (Spring Boot, Next.js, Kafka, Keycloak, Vault, Grafana, K3s, ArgoCD, Jenkins, Gitea, Kong, OpenFaaS, etc.)
- **Restricciones de costo que afecten decisiones de diseño:** Minimizar costos de cloud usando el tier Always Free de OCI (Ampere A1.Flex) en producción; evitar servicios gestionados de cloud (RDS, DocumentDB, MSK) que generan costos variables altos; toda la infraestructura corre en el VPS nativo con K3s.

---

## 11. Restricciones Organizacionales

- El sistema debe desplegarse exclusivamente sobre la infraestructura cloud aprobada por el Área de TI: VPS Oracle Cloud OCI en producción, VM QEMU/KVM local en desarrollo (sin uso de otros proveedores cloud).
- El stack tecnológico está definido y es mandatorio según los scripts y templates del framework SDLC del proyecto (`.claude/scripts/` y `.claude/templates/`); no se pueden incorporar tecnologías no definidas en ese framework sin revisión y aprobación explícita.
- Las contraseñas y credenciales de servicios nunca deben commitearse en el repositorio; deben gestionarse exclusivamente a través de HashiCorp Vault con el path `controlstock/<env>/<servicio>`.
- El proceso CI/CD debe implementarse desde las etapas iniciales del desarrollo (RNF-010); no se acepta despliegue manual a producción.
- Las metodologías de desarrollo son DDD, BDD y ATDD (restricción técnica del SRS, sección 8); todo el código de dominio debe seguir separación clara entre dominio, aplicación e infraestructura.
- El registro de auditoría (RF-017) debe ser inmutable y no modificable por ningún usuario ni proceso; es una restricción de negocio no negociable (RN-011).

---

## 12. Decisiones Previas Ya Tomadas

| Decisión | Resultado | Quién decidió | Fecha |
|----------|-----------|---------------|-------|
| Infraestructura base (VPS local QEMU/KVM + OCI en prod, K3s, Terraform/Helm) | Adoptada como estándar del framework SDLC | Arquitectura SDLC del proyecto | 2026-06-12 |
| Stack de backend: Java 21 + Spring Boot 3.4.x + WebFlux + arquitectura hexagonal Maven | Mandatorio según `maven_hexagonal_scaffold.py` | Framework SDLC | 2026-06-12 |
| Stack de frontend: Next.js 15 + TypeScript + React 19 + TailwindCSS | Mandatorio según `nextjs_feature_scaffold.py` | Framework SDLC | 2026-06-12 |
| Patrón CQRS con PostgreSQL 16 (command) + MongoDB 7 (read model) | Mandatorio por infraestructura y templates | Framework SDLC | 2026-06-12 |
| Mensajería: Apache Kafka 3.8 (Strimzi en K3s) | Mandatorio según `base-infrastructure-builder.sh` | Framework SDLC | 2026-06-12 |
| Autenticación: Keycloak + Kong Gateway JWT RS256 | Mandatorio según `base-infrastructure-builder.sh` | Framework SDLC | 2026-06-12 |
| Gestión de secretos: HashiCorp Vault KV v2 | Mandatorio según `base-infrastructure-builder.sh` | Framework SDLC | 2026-06-12 |
| Observabilidad: Prometheus + Grafana + Loki + Grafana Tempo + OTel Java Agent | Mandatorio según `base-infrastructure-builder.sh` | Framework SDLC | 2026-06-12 |
| CI/CD: Jenkins + ArgoCD (GitOps) + Gitea | Mandatorio según `base-infrastructure-builder.sh` | Framework SDLC | 2026-06-12 |
| Capa de integración: `integration-service` con Apache Camel 4.10.2 + saga Narayana LRA | Mandatorio según `integration_service_scaffold.py` | Framework SDLC | 2026-06-12 |
| Reportería: ETL Scala + Spark + OpenFaaS + MinIO | Mandatorio según `scala_hexagonal_scaffold.py` y `report_lambdas_scaffold.py` | Framework SDLC | 2026-06-12 |
| Migraciones BD: Liquibase standalone (incompatible con R2DBC; no Flyway) | Mandatorio según `maven_hexagonal_scaffold.py` | Framework SDLC | 2026-06-12 |

---

## 13. Reportería

- **¿El sistema requiere generación de reportes?** Sí (RF-015, RF-016)
- **Fuente de datos del ETL:** Read model CQRS (MongoDB 7) como fuente principal; PostgreSQL 16 vía JDBC para datos de auditoría y ajustes que aún no estén materializados en el read model
- **Disparo del ETL:** Ambos — programado/schedule (reportes periódicos de cierre) y on-demand por evento de comando (cuando el usuario genera un reporte desde el módulo de reportería, RF-015)
- **Persistencia del catálogo de esquemas:** Tabla `report_schema_catalog` en PostgreSQL (BD del servicio de reportería)

### Tipos de reporte

| Tipo de reporte (`reportType`) | Fuente (colección/tabla) | Columnas/esquema esperado | Formatos de salida | Frecuencia / disparo | Volumetría estimada |
|---|---|---|---|---|---|
| `stock-actual` | Colección `productos` (read model MongoDB) | código, nombre, categoría, unidad de medida, stock_actual, stock_mínimo, stock_máximo, estado | PDF / XLS / CSV | On-demand | ~10 K filas/reporte |
| `movimientos-periodo` | Colección `movimientos` (read model MongoDB) | fecha, producto, tipo_movimiento, cantidad, saldo, referencia, usuario | PDF / XLS / CSV | On-demand / mensual programado | ~50 K filas/mes |
| `kardex-producto` | Colección `kardex` (read model MongoDB) | fecha, tipo, cantidad, saldo_acumulado, referencia, usuario | PDF / XLS / CSV | On-demand | ~5 K filas/producto |
| `stock-bajo-minimo` | Colección `productos` (read model MongoDB) | código, nombre, categoría, stock_actual, stock_mínimo, diferencia | PDF / XLS / CSV | On-demand / diario programado | ~500 filas/reporte |
| `proveedores-actividad` | Colección `proveedores` + `movimientos` (read model MongoDB) | proveedor, método_integración, movimientos_período, último_abastecimiento | PDF / XLS / CSV | On-demand / mensual programado | ~200 filas/reporte |
| `auditoria-operaciones` | Tabla `audit_log` (PostgreSQL — inmutable) | fecha, usuario, operación, entidad, id_entidad, valor_anterior, valor_nuevo | PDF / XLS / CSV | On-demand / bajo demanda del auditor | ~100 K filas/mes |

---

## 14. Información Adicional

### Microservicios identificados (preliminar, a confirmar en etapa de diseño)

Con base en los bounded contexts derivados del SRS y los patrones del framework SDLC:

| Microservicio | Responsabilidad principal | BD escritura | Mensajería |
|---|---|---|---|
| `catalog-service` | Gestión de productos y categorías (RF-004, RF-005) | PostgreSQL | Kafka producer (eventos de catálogo) |
| `inventory-service` | Control de stock, registro de movimientos, Kardex (RF-006, RF-007, RF-008, RF-010) | PostgreSQL + Outbox | Kafka producer/consumer |
| `adjustment-service` | Flujo de ajustes con aprobación (RF-009) | PostgreSQL + Outbox | Kafka producer |
| `alert-service` | Motor de alertas automáticas (RF-012) | PostgreSQL | Kafka consumer; REST saliente a `integration-service` |
| `supplier-service` | Gestión de proveedores (RF-013) | PostgreSQL | Kafka producer |
| `report-service` | Orquestación de reportes, catálogo de esquemas (RF-015, RF-016) | PostgreSQL | Kafka producer (dispara ETL) |
| `audit-service` | Registro inmutable de auditoría (RF-017) | PostgreSQL (append-only) | Kafka consumer |
| `user-service` | Gestión de usuarios, roles y permisos RBAC (RF-001, RF-002, RF-003) | PostgreSQL | — |
| `integration-service` | ACL con proveedores externos y servicio de notificaciones; orquestador de saga (RF-018, RF-019) | PostgreSQL | Kafka consumer/producer; Apache Camel; Narayana LRA |
| `report-etl-service` | ETL batch (Scala + Spark): extracción desde MongoDB read model, transformación y generación de Parquet en MinIO | — (Spark jobs) | Kafka consumer/producer |
| `frontend` (Next.js) | Interfaz web responsive (todos los RF de UI) | — | REST → Kong → microservicios |

### Notas sobre el API Gateway (Kong)

Todos los microservicios backend se exponen únicamente a través de Kong (puerto 8000 del VPS). El frontend Next.js consume `NEXT_PUBLIC_API_BASE_URL=http://VPS_IP:8000`. Kong valida el JWT de Keycloak (plugin `jwt`, RS256, `iss = keycloak_url/realms/controlstock`) y aplica rate-limiting global (200 req/min). Los endpoints internos entre microservicios usan service-to-service DNS de K3s (`<servicio>.apps.svc.cluster.local`) sin pasar por Kong.

### Notas sobre la API pública (RF-020)

La API REST pública de ControlStock expuesta a sistemas externos se gestiona como un contexto de integración separado dentro de Kong, con tokens de API independientes de los tokens de sesión de usuario. Los permisos de la API se administran por el módulo RBAC (RF-003) con roles específicos para integraciones externas.

---

*Documento generado como parte de la etapa de Planeación del SDLC — ControlStock.*  
*Referencia: SRS-ControlStock.md v1.0 | Framework SDLC: `.claude/scripts/` y `.claude/templates/`*
