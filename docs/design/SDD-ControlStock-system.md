# Software Design Document — Arquitectura del Sistema

**Proyecto:** ControlStock | Parte del conjunto SDD Técnico — etapa Diseño Técnico del SDLC.
Documentos complementarios: `SDD-ControlStock-design.md` · `SDD-ControlStock-infrastructure.md`

---

## 1. Introducción

### Propósito

Este documento define la arquitectura técnica del sistema ControlStock, el stack tecnológico adoptado, la descripción de cada componente y la organización modular interna. Constituye la base de referencia para la implementación de los 9 bounded contexts definidos en el Strategic Design.

### Objetivo Técnico

Traducir las decisiones estratégicas (DS-001 a DS-010, DS-CQRS-1/2/3) en una solución de ingeniería concreta: microservicios hexagonales con CQRS event-driven, capa de integración centralizada, sagas orquestadas y stack de reportería batch sobre un cluster K3s self-hosted.

### Alcance del Diseño

Cubre los 9 bounded contexts (BC-01 a BC-09), el stack de reportería (report-etl-service + report-format-consumer), las bases de datos por servicio (Database-per-Service), el read model CQRS en MongoDB y la infraestructura sobre K3s en dos ambientes: VM QEMU/KVM local (dev) y VPS Oracle Cloud OCI (prod).

### Contexto del Sistema

ControlStock es un sistema web centralizado de gestión de inventario para el dominio Retail / Logística. Reemplaza procesos manuales en hojas de cálculo con control de stock en tiempo real, trazabilidad completa, alertas automáticas, integración con proveedores externos y reportería ejecutiva exportable.

---

## 2. Arquitectura General

### Estilo Arquitectónico

**Microservicios con Diseño Hexagonal (DDD) + Event-Driven (CQRS)**

Cada bounded context se implementa como un microservicio independiente con arquitectura hexagonal: núcleo de dominio aislado de la infraestructura, puertos y adaptadores explícitos. La comunicación entre servicios es asíncrona mediante Kafka (eventos de dominio vía Transactional Outbox) para operaciones que no requieren respuesta inmediata, y síncrona mediante REST interno K3s para consultas o coordinación directa.

### Organización General

```
Usuario / Sistema Externo
        │
        ▼
  [Traefik / Kong]  ← DMZ / Gateway
        │
        ▼
  [Microservicios de Dominio]  ← Zona de Aplicación (namespace: apps)
        │
      ┌─┴─────────────────────────────┐
      │ Kafka (eventos)               │ REST interno K3s
      ▼                               ▼
  [audit-service]            [integration-service] ← ACL + Saga Orchestrator
  [alert-service]                     │
  [projection consumers]              ▼
        │               [Sistemas Externos / Narayana LRA]
        ▼
  [MongoDB read model]
        │
        ▼
  [report-etl-service] → MinIO → [report-format-consumer]
```

### Capas del Sistema

| Capa | Responsabilidad | Componentes |
|---|---|---|
| Gateway / DMZ | Autenticación JWT RS256, rate limiting, CORS, enrutamiento | Traefik (frontend), Kong API Gateway |
| Dominio | Lógica de negocio por bounded context, invariantes, eventos | 9 microservicios Spring Boot (iam, catalog, inventory, adjustment, alert, supplier, report, audit, integration) |
| Mensajería | Bus de eventos asíncronos; Transactional Outbox relay | Apache Kafka (Strimzi KRaft) |
| Read Model | Proyecciones desnormalizadas para Kardex, dashboard y ETL | MongoDB 7 (`controlstock_readmodel`) |
| Reportería | ETL batch y conversión de formatos | report-etl-service (Spark CronJob) + report-format-consumer (OpenFaaS) |
| Persistencia | Command side transaccional por servicio | PostgreSQL 16 por bounded context (9 bases independientes) |
| Identidad | Autenticación OIDC, emisión y revocación de JWT | Keycloak 24 (realm controlstock) |
| Secretos | Credenciales en runtime, sin secretos en código | HashiCorp Vault KV v2 |

### Diagramas C4

**Diagrama de Contexto (C4 Nivel 1):** Muestra a ControlStock como sistema único en relación con sus 6 tipos de actores internos (Operador, Supervisor, Administrador, Gerente/Analista, Auditor, API Consumer Externo) y 3 sistemas externos (Servicio de Notificaciones, API REST de Proveedor, Servidor FTP/SFTP de Proveedor).

Ver diagrama: [SDD-ControlStock-c4-context.mmd](diagrams/SDD-ControlStock-c4-context.mmd)

**Diagrama de Contenedores (C4 Nivel 2):** Muestra todos los contenedores internos del cluster K3s: frontend (Next.js), Kong (API Gateway), 9 microservicios de dominio, integration-service (ACL + Saga), Narayana LRA coordinator, report-etl-service (CronJob Spark), report-format-consumer (OpenFaaS), 9 bases de datos PostgreSQL, MongoDB read model, MinIO, Apache Kafka, Keycloak y HashiCorp Vault. El `integration-service` se posiciona como único intermediario entre los microservicios de dominio y todos los sistemas externos.

Ver diagrama: [SDD-ControlStock-c4-container.mmd](diagrams/SDD-ControlStock-c4-container.mmd)

---

## 3. Stack Tecnológico

| Categoría | Tecnología | Razón |
|---|---|---|
| Backend | Spring Boot 3.x / Java 21 (virtual threads) | Stack mandatorio ADC; R2DBC reactivo; bajo overhead de memoria; soporte Micrometer para Prometheus |
| Frontend | Next.js 14 / React 18 / TypeScript | Stack mandatorio ADC; App Router con SSR; client components para dashboard reactivo |
| Base de Datos — Command Side | PostgreSQL 16 | ACID para escritura de stock; soporte R2DBC reactivo; jsonb para payload de outbox; Liquibase migrations |
| Base de Datos — Read Model | MongoDB 7 | Documentos desnormalizados para Kardex/dashboard/ETL; latencia p95 < 2 s en consultas; Spark MongoDB Connector |
| Mensajería | Apache Kafka (Strimzi KRaft) | Desacoplamiento async; Transactional Outbox; at-least-once; ACLs TLS por productor/consumidor |
| Integración | Apache Camel 4.10.2 | EIP para protocolos heterogéneos (REST, FTP/SFTP); camel-reactive-streams (bridge reactivo Camel↔Reactor); Resilience4j circuit breaker por sistema externo |
| ETL / Reportería | Apache Spark 3.5.1 / Scala 2.13 | Stack mandatorio ADC; patrón Factory por ReportType; Spark MongoDB Connector + Spark JDBC |
| Formatos de Reporte | OpenFaaS (python3-http) + Kafka Connector (Helm) | Serverless event-driven; sin servidor persistente para conversión de archivos; desplegado en K3s |
| Almacenamiento de Objetos | MinIO (K3s dev) / OCI Object Storage (prod) | S3-compatible; .parquet intermedios + archivos finales XLSX/CSV/PDF |
| Autenticación | Keycloak 24 (realm controlstock) | OIDC/OAuth 2.0 mandatorio; JWT RS256; gestión de sesiones y revocación; namespace identity |
| API Gateway | Kong 3.x | Validación JWT RS256 centralizada; rate limiting 200 req/min; CORS; RBAC por endpoint; NodePort 8000 |
| Secretos | HashiCorp Vault KV v2 (`controlstock/<env>/<svc>`) | Credenciales en runtime via `spring-cloud-vault-config`; rotación sin redeploy; AppRole auth; namespace secrets |
| Sagas | Apache Camel Saga EIP + Narayana LRA 7.x | Orquestación LRA centralizada en integration-service; compensaciones idempotentes; persistencia en saga_instance |
| Infraestructura / Orquestación | K3s (dev + prod), Terraform + provider Helm (IaC), Traefik (ingress) | Stack mandatorio ADC; self-hosted OCI; script `base-infrastructure-builder.sh` genera terraform/ en tiempo de ejecución |
| Registry de Imágenes | Gitea Package Registry OCI (dev) / OCIR Oracle Container Registry (prod) | Registry incluido en el stack self-hosted; digest de imagen verificado por ArgoCD |
| CI/CD | Jenkins (pipelines por servicio) + ArgoCD (GitOps) + Gitea (repos + webhooks) | Pipeline completo: build → test → SonarQube quality gate → Trivy scan → push imagen → ArgoCD sync |
| Observabilidad | kube-prometheus-stack (Prometheus + Grafana + AlertManager) + Loki + Promtail + Grafana Tempo | Stack mandatorio ADC; métricas, logs JSON estructurados y trazas OTLP en un solo stack |

---

## 4. Componentes del Sistema

### Componente: iam-service (BC-01)

**Responsabilidades**
- Gestionar el ciclo de vida de usuarios en Keycloak realm `controlstock` (alta, modificación, inactivación).
- Administrar roles y permisos RBAC con granularidad por módulo y operación.
- Exponer endpoints para asignación/revocación de roles a usuarios.
- Mantener la proyección local `controlstock_iam` sincronizada con Keycloak.

**Dependencias**
- Keycloak 24 (realm controlstock) — OIDC/OAuth 2.0.
- PostgreSQL `controlstock_iam` (R2DBC) — persistencia local de usuarios/roles/permisos.
- HashiCorp Vault — secretos de BD en runtime.

---

### Componente: catalog-service (BC-02)

**Responsabilidades**
- Alta, modificación e inactivación de productos y categorías.
- Validar unicidad de código de producto y la invariante `stock_mínimo < stock_máximo`.
- Impedir inactivación de categorías con productos activos.
- Publicar `ProductoCreado`, `ProductoActualizado`, `ProductoInactivado` vía Transactional Outbox → Kafka.
- Proyectar colección `productos` en MongoDB read model (projection consumer Kafka).

**Dependencias**
- PostgreSQL `controlstock_catalog` (R2DBC).
- MongoDB `controlstock_readmodel` — escritura de proyección `productos`.
- Kafka (productor + projection consumer).
- HashiCorp Vault — secretos de BD.

---

### Componente: inventory-service (BC-03)

**Responsabilidades**
- Mantener `StockLevel` actualizado de forma atómica con el registro de cada movimiento.
- Registrar entradas y salidas de inventario; impedir salidas sin stock suficiente.
- Crear `KardexRecord` append-only tras cada movimiento (historial inmutable).
- Aplicar el impacto en stock de ajustes aprobados recibidos via Kafka (Saga-02, consumidor idempotente).
- Publicar `EntradaRegistrada`, `SalidaRegistrada`, `StockActualizado` vía Outbox → Kafka.
- Proyectar colecciones `kardex`, `movimientos`, `stock` en MongoDB read model.
- Exponer endpoint de compensación `POST /inventory/movements/{id}/compensar` para Saga-01.

**Dependencias**
- PostgreSQL `controlstock_inventory` (R2DBC).
- MongoDB `controlstock_readmodel` — escritura de proyecciones.
- Kafka (productor vía Outbox + consumidor de `AjusteAprobado`).
- HashiCorp Vault — secretos de BD.

---

### Componente: adjustment-service (BC-04)

**Responsabilidades**
- Crear `AdjustmentRequest` en estado Pendiente con motivo obligatorio.
- Registrar decisiones de aprobación o rechazo con usuario decisor.
- Publicar `AjusteAprobado` o `AjusteRechazado` vía Outbox → Kafka para que Inventory aplique el impacto.
- Exponer endpoint de compensación `POST /adjustments/{id}/compensar` para Saga-02.

**Dependencias**
- PostgreSQL `controlstock_adjustment` (R2DBC).
- Kafka (productor vía Outbox).
- HashiCorp Vault — secretos de BD.

---

### Componente: alert-service (BC-05)

**Responsabilidades**
- Consumir `StockActualizado` desde Kafka; evaluar umbrales `stock_mínimo` y `stock_máximo` por producto.
- Generar `AlertaBajoStock` (`stock_actual ≤ stock_mínimo`) y `AlertaSobrestock` (`stock_actual ≥ stock_máximo`).
- Registrar `AlertEvent` en BD independientemente del resultado del envío externo.
- Solicitar el envío de notificación al `integration-service` vía REST interno K3s.

**Dependencias**
- PostgreSQL `controlstock_alert` (R2DBC).
- Kafka (consumidor de `StockActualizado`).
- `integration-service` — REST interno K3s para envío de notificaciones.
- HashiCorp Vault — secretos de BD.

---

### Componente: supplier-service (BC-06)

**Responsabilidades**
- Registrar, modificar e inactivar proveedores; impedir eliminación de proveedores con movimientos asociados.
- Almacenar la configuración de integración con referencia al path en Vault (nunca credenciales en texto plano).
- Proyectar colección `proveedores` en MongoDB read model para el ETL del reporte de actividad de proveedores.

**Dependencias**
- PostgreSQL `controlstock_supplier` (R2DBC).
- MongoDB `controlstock_readmodel` — escritura de proyección `proveedores`.
- Kafka (productor de `ProveedorActualizado`).
- HashiCorp Vault — secretos de BD + paths de credenciales de proveedores.

---

### Componente: report-service (BC-07)

**Responsabilidades**
- Gestionar el ciclo de vida de `ReportRequest` (Solicitado → Procesando → Completado/Fallido).
- Mantener el catálogo de esquemas de reporte (`report_schema_catalog`).
- Publicar solicitud de generación a Kafka para activar el ETL on-demand.
- Proveer URLs de descarga de archivos en MinIO a usuarios autorizados.

**Dependencias**
- PostgreSQL `controlstock_reporting` (R2DBC).
- Kafka (productor de solicitud de reporte).
- MinIO / OCI Object Storage — URLs de archivos generados.
- HashiCorp Vault — secretos de BD.

---

### Componente: audit-service (BC-08)

**Responsabilidades**
- Consumir todos los eventos de dominio relevantes desde Kafka.
- Persistir cada operación como `AuditRecord` append-only con usuario, timestamp UTC y valores antes/después.
- Proveer endpoint de consulta del log de auditoría a usuarios con permiso explícito (rol Auditor / Administrador).

**Dependencias**
- PostgreSQL `controlstock_audit` (R2DBC, append-only).
- Kafka (consumidor de todos los topics de eventos de dominio).
- HashiCorp Vault — secretos de BD.

---

### Componente: integration-service (BC-09 — ACL + Saga Orchestrator)

**Responsabilidades**
- Actuar como Anti-Corruption Layer (ACL) centralizado entre ControlStock y todos los sistemas externos.
- Gestionar conectividad con el servicio de notificaciones externo (Camel `http` component; reintentos con backoff exponencial; Circuit Breaker Resilience4j).
- Gestionar integración con proveedores externos REST y FTP/SFTP (Camel `http` y `file` components; ACL por proveedor; traducción de modelos externos al lenguaje ubicuo).
- Orquestar Saga-01 (reposición de inventario) y Saga-02 (ajuste con aprobación) mediante Camel Saga EIP + Narayana LRA.
- Exponer la API pública de ControlStock para sistemas externos consumidores (RF-020), coordinada con Kong.
- Registrar en `integration_logs` el resultado de cada integración para trazabilidad.

**Dependencias**
- PostgreSQL `controlstock_integration` (R2DBC) — logs, saga_instance, saga_step_log, outbox.
- Kafka (productor + consumidor de eventos de saga).
- Narayana LRA Coordinator (namespace infra, port 50000) — protocolo LRA.
- HashiCorp Vault — credenciales de proveedores en runtime (spring-cloud-vault-config).
- Sistemas externos: Servicio de Notificaciones, APIs REST de Proveedores, FTP/SFTP de Proveedores.

---

### Componente: report-etl-service (BC-07 — Batch)

**Responsabilidades**
- Ejecutarse como CronJob K8s (schedule configurable) o bajo demanda al consumir evento Kafka de solicitud.
- Extraer datos del read model MongoDB vía Spark MongoDB Connector; para reportes de auditoría, leer `controlstock_audit` vía Spark JDBC.
- Consultar `report_schema_catalog` en `controlstock_reporting` para validar el DataFrame extraído (patrón Factory por `ReportType`).
- Generar archivo `.parquet` en MinIO (`controlstock-reports/parquet/`).
- Publicar evento `ReporteParquetGenerado` (DE-020) con URL del .parquet y formato destino.

**Dependencias**
- MongoDB `controlstock_readmodel` — Spark MongoDB Connector (lectura).
- PostgreSQL `controlstock_audit` — Spark JDBC (lectura del audit_log para reportes de auditoría).
- PostgreSQL `controlstock_reporting` — Spark JDBC (lectura del report_schema_catalog).
- MinIO / OCI Object Storage — escritura de .parquet.
- Kafka (productor de `ReporteParquetGenerado`).

---

### Componente: report-format-consumer (BC-07 — Serverless)

**Responsabilidades**
- Invocarse al recibir `ReporteParquetGenerado` vía OpenFaaS Kafka Connector.
- Leer el .parquet desde MinIO.
- Generar el archivo final en el formato indicado en el evento (XLSX, CSV o PDF).
- Almacenar el archivo final en MinIO (`controlstock-reports/output/{xlsx,csv,pdf}/`).
- Notificar al report-service el URL del archivo generado para actualizar el `ReportRequest` a estado Completado.

**Dependencias**
- MinIO / OCI Object Storage — lectura de .parquet y escritura de archivo final.
- Kafka (via OpenFaaS Kafka Connector).
- `report-service` — REST interno K3s para callback de finalización.

---

## 5. Diseño de Módulos

Todos los microservicios Spring Boot implementan arquitectura hexagonal con las siguientes capas:

### Capas Comunes (Hexagonal)

| Capa | Paquete | Contenido |
|---|---|---|
| **Domain** | `domain/model` | Aggregates, Entities, Value Objects, Domain Events |
| **Domain** | `domain/port` | Interfaces (puertos): `inbound` (casos de uso), `outbound` (repositorios, event publisher) |
| **Application** | `application/usecase` | Implementaciones de los puertos inbound; orquesta el dominio |
| **Application** | `application/event` | Handlers de eventos internos |
| **Infrastructure** | `infrastructure/persistence` | Adaptadores R2DBC / MongoDB; implementan puertos outbound de repositorio |
| **Infrastructure** | `infrastructure/messaging` | Outbox relay (scheduler R2DBC), projection consumers Kafka |
| **Infrastructure** | `infrastructure/web` | Controllers REST (adaptadores inbound HTTP); mappers de DTOs |
| **Infrastructure** | `infrastructure/config` | Spring config, Vault config, seguridad, Kafka beans |

### Módulos Específicos de integration-service

Además de las capas hexagonales estándar, `integration-service` incluye:

| Módulo | Responsabilidad |
|---|---|
| `camel/routes` | Rutas Camel por sistema externo (notificaciones, proveedor-REST, proveedor-FTP); ACL por proveedor |
| `camel/saga` | Camel Saga EIP; definición de pasos, compensaciones y políticas de timeout por saga |
| `camel/resilience` | Configuración Resilience4j (circuit breaker, retry, bulkhead) por ruta Camel |
| `lra` | Integración con Narayana LRA coordinator; registro de participantes |

### Comunicación entre Módulos

- **Dominio → Aplicación:** puertos inbound (interfaces).
- **Aplicación → Dominio:** llamadas directas al modelo de dominio.
- **Aplicación → Infraestructura:** puertos outbound (interfaces implementadas por adaptadores).
- **Cross-service sync:** REST interno K3s (sin pasar por Kong) para alert-service → integration-service.
- **Cross-service async:** Kafka con Transactional Outbox; los consumidores garantizan idempotencia via `processed_message`.
