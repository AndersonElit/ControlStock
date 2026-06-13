# Etapa 3g — Microservicio: Report Service (BC-07)

## Tabla de Contenidos

1. [Contexto y Responsabilidad](#contexto-y-responsabilidad)
2. [Prerrequisitos](#prerrequisitos)
3. [Ciclo de Desarrollo Incremental en K3s VPS dev](#ciclo-de-desarrollo-incremental-en-k3s-vps-dev)
4. [Capa de Dominio](#capa-de-dominio)
5. [Capa de Aplicación](#capa-de-aplicación)
6. [Capa de Infraestructura](#capa-de-infraestructura)
7. [API REST](#api-rest)
8. [Especificación TDD por Capa (Red-Green-Refactor)](#especificación-tdd-por-capa-red-green-refactor)
9. [Criterios de Aceptación](#criterios-de-aceptación)

---

## Contexto y Responsabilidad

El **Report Service** (Bounded Context BC-07) es el microservicio responsable de gestionar el ciclo de vida de solicitudes de generación de reportes en ControlStock. Es el **séptimo microservicio en implementarse**. Orquesta la solicitud de reportes mediante publicación de eventos a Kafka (que activa el ETL), recibe callbacks del `report-format-consumer` y provee URLs de descarga seguras con tiempo de vida limitado desde MinIO.

### Responsabilidades del servicio

| Responsabilidad | Descripción |
|----------------|-------------|
| **Gestión del ciclo de vida de ReportRequest** | Transiciones: `SOLICITADO → PROCESANDO → COMPLETADO / FALLIDO` |
| **Mantenimiento del catálogo de esquemas** | `report_schema_catalog` define los tipos de reporte disponibles y sus columnas |
| **Publicación de solicitudes a Kafka** | Publicar `SolicitudReporteGenerada` (topic `controlstock.reporting.requests`) para activar el ETL on-demand |
| **Recepción de callback del report-format-consumer** | `POST /reports/{id}/completar` — marca COMPLETADO y almacena URL MinIO en `report_files` |
| **Recepción de fallo vía Kafka** | Consumir `ReporteETLFallido` para marcar la solicitud como FALLIDO |
| **Generación de URLs de descarga seguras** | Proveer pre-signed URL de MinIO (TTL 15 minutos) en `GET /reports/{id}/download` |

### Lo que el servicio NO hace

| Restricción | Justificación |
|-------------|---------------|
| No genera ni almacena archivos de reporte | El `report-etl-service` genera el Parquet/CSV/XLSX y lo sube a MinIO; este servicio solo guarda la URL |
| No interactúa directamente con MinIO para escritura | Solo genera pre-signed URLs de lectura para descarga por el usuario final |
| No participa en sagas | Implementa un patrón de orquestación via Kafka sin compensación distribuida |
| No tiene dependencias REST de otros servicios de dominio | Solo depende de Keycloak para autenticación y del MinIO SDK para pre-signed URLs |
| No valida el contenido de los datos del reporte | El ETL es responsable de la coherencia de los datos; report-service solo gestiona metadatos |

### Bounded Context BC-07

```
┌──────────────────────────────────────────────────────────────────────┐
│                    Report Service (BC-07)                            │
│                                                                      │
│  ┌────────────────────────┐    ┌────────────────────────────────┐    │
│  │  report_schema_catalog │    │       report_requests          │    │
│  │  (seeds por tipo)      │◄───│  SOLICITADO → PROCESANDO       │    │
│  └────────────────────────┘    │  → COMPLETADO / FALLIDO        │    │
│                                └───────────────┬────────────────┘    │
│                                                │                     │
│                                                ▼                     │
│                                    ┌─────────────────────┐           │
│                                    │    report_files      │           │
│                                    │  - url_minio         │           │
│                                    │  - formato           │           │
│                                    │  - tamanio_bytes     │           │
│                                    └──────────────────────┘          │
└──────────────────────────────────────────────────────────────────────┘
    │ (produce)                              │ (consume)
    ▼                                        ▼
┌───────────────────────────────┐   ┌───────────────────────────────┐
│  Apache Kafka                 │   │  Apache Kafka                 │
│  controlstock.reporting       │   │  controlstock.reporting       │
│  .requests                    │   │  .etl-fallido                 │
│  (SolicitudReporteGenerada)   │   │  (ReporteETLFallido)          │
│  → activa report-etl-service  │   │  → marca ReportRequest FALLIDO│
└───────────────────────────────┘   └───────────────────────────────┘

    ▲ (REST callback)
    │
┌────────────────────────────────┐
│  report-format-consumer        │
│  POST /reports/{id}/completar  │
│  POST /reports/{id}/fallar     │
│  (notifica URL MinIO del file) │
└────────────────────────────────┘

                    ┌─────────────────────────────────────┐
                    │  MinIO (S3-compatible)              │
                    │  - Pre-signed URL (TTL 15 min)      │
                    │    para descarga del archivo        │
                    │  - Solo lectura desde report-service│
                    └─────────────────────────────────────┘
```

### Base de datos

- **PostgreSQL 16** — schema `controlstock_reporting` (report_schema_catalog, report_requests, report_files)
- **Tecnología de acceso**: Spring Data R2DBC (reactivo)
- **No hay MongoDB**: este servicio no mantiene proyecciones de lectura

---

## Prerrequisitos

| Prerrequisito | Documento de referencia | Verificación |
|--------------|------------------------|-------------|
| Etapa 0 — Infraestructura base completa | `DEV-ControlStock-00-infrastructure.md` | K3s corriendo, namespaces activos |
| Etapa 0c — Observabilidad configurada | `DEV-ControlStock-0c-observability.md` | Prometheus + Grafana activos |
| Etapa 1 — Bases de datos aprovisionadas | `DEV-ControlStock-01-databases.md` | PostgreSQL schema `controlstock_reporting` + seeds en `report_schema_catalog` |
| Etapa 2 — Scaffold generado | `DEV-ControlStock-02-scaffold.md` | Proyecto Maven `report-service` generado |
| Etapa 2b — Pipeline CI/CD configurado | `DEV-ControlStack-02b-cicd.md` | Job `report-service` activo en Jenkins |
| **Etapa 3a — IAM Service corriendo** | `DEV-ControlStock-03-ms-iam-service.md` | Keycloak emitiendo tokens JWT con roles para realm `controlstock` |
| Kafka (Strimzi KRaft) corriendo | Etapa 0 | Topics `controlstock.reporting.*` creados |
| MinIO corriendo | Etapa 0 | Bucket `controlstock-reports` creado; credenciales en Vault |
| `report-etl-service` y `report-format-consumer` | Implementados después de este servicio | Pueden testearse con stubs/mocks en integración |

### Verificación de prerrequisitos

```bash
# Verificar schema PostgreSQL reporting y seeds del catálogo
kubectl exec -n databases deploy/postgresql -- psql \
  -U controlstock_reporting -d controlstock_reporting \
  -c "\dt" | grep -E "report_schema_catalog|report_requests|report_files"

kubectl exec -n databases deploy/postgresql -- psql \
  -U controlstock_reporting -d controlstock_reporting \
  -c "SELECT report_type FROM report_schema_catalog;"
# Salida esperada:
# stock-actual
# movimientos-periodo
# auditoria-operaciones
# proveedores-actividad

# Verificar topics Kafka reporting
kubectl exec -n kafka deploy/kafka -- \
  kafka-topics.sh --list --bootstrap-server kafka:9092 \
  | grep "controlstock.reporting"
# Salida esperada:
# controlstock.reporting.etl-fallido
# controlstock.reporting.requests

# Verificar MinIO bucket
kubectl exec -n minio deploy/minio -- mc ls local/controlstock-reports

# Verificar token JWT con rol Gerente/Analista
TOKEN=$(curl -s -X POST \
  "http://<VPS_IP>:8180/realms/controlstock/protocol/openid-connect/token" \
  -d "client_id=test-client&grant_type=password&username=gerente@test.com&password=test" \
  | jq -r '.access_token')
echo $TOKEN | cut -d'.' -f2 | base64 -d | jq '.realm_access.roles'
```

---

## Ciclo de Desarrollo Incremental en K3s VPS dev

```
┌──────────────────────────────────────────────────────┐
│               Ciclo de Desarrollo TDD                │
│                                                      │
│  1. Escribir test RED (falla esperada)               │
│         │                                            │
│         ▼                                            │
│  2. Implementar el mínimo código GREEN               │
│         │                                            │
│         ▼                                            │
│  3. REFACTOR — mejorar diseño                        │
│         │                                            │
│         ▼                                            │
│  4. git push → Gitea webhook → Jenkins pipeline      │
│         │                                            │
│         ▼                                            │
│  5. bumpImageTag → ArgoCD sync → K3s pod             │
│         │                                            │
│         ▼                                            │
│  6. Verificar /actuator/health + prueba manual       │
│                                                      │
│  Condición mínima para primer deploy:                │
│  - Dominio compila; contexto Spring arranca          │
│  - GET /actuator/health/readiness → 200              │
└──────────────────────────────────────────────────────┘
```

### Orden de implementación incremental

| Incremento | Capa | Contenido | Condición de avance |
|-----------|------|-----------|-------------------|
| **I-1** | Dominio | Entidad `ReportRequest`; VO `ReportType`, `ReportRequestId`, `UsuarioId`; transiciones de estado (`SOLICITADO → PROCESANDO → COMPLETADO / FALLIDO`) | Tests dominio GREEN |
| **I-2** | Dominio | Entidad `ReportFile`; VO `MinioUrl`, `TamanioBytesVO`; regla: `url_minio` no vacía | Tests VOs GREEN |
| **I-3** | Dominio | Eventos de dominio: `SolicitudReporteGenerada`; regla: solo puede descargarse si `COMPLETADO` | Tests transiciones GREEN |
| **I-4** | Dominio | Puertos: `ReportRequestRepository`, `ReportFileRepository`, `ReportSchemaCatalogRepository`, `KafkaReportPublisher`, `MinioPresignedUrlPort` | Interfaces definidas; compilación GREEN |
| **I-5** | Aplicación | `SolicitarReporteUseCase` (valida tipo, publica Kafka, crea `ReportRequest` SOLICITADO) | Tests aplicación con mocks GREEN |
| **I-6** | Aplicación | `CompletarReporteUseCase` (callback completar: COMPLETADO + crea ReportFile), `FallarReporteUseCase` | Tests transiciones GREEN |
| **I-7** | Aplicación | `DescargarReporteUseCase` (valida COMPLETADO, genera pre-signed URL MinIO 15 min) | Tests pre-signed URL GREEN |
| **I-8** | Infraestructura | R2DBC adapters para `report_requests`, `report_files`, `report_schema_catalog` | Tests Testcontainers (PostgreSQL) GREEN |
| **I-9** | Infraestructura | Kafka producer (`SolicitudReporteGenerada`) + Kafka consumer (`ReporteETLFallido`) | Tests Testcontainers (PostgreSQL + Kafka) GREEN |
| **I-10** | Infraestructura | MinIO adapter (pre-signed URL generación) | Tests con MinIO mock/stub GREEN |
| **I-11** | API REST | Endpoints completos + `@ExceptionHandler` (400, 403, 404, 409) | Tests `@WebFluxTest` GREEN |
| **I-12** | Integración | Tests E2E en K3s: solicitud → Kafka → callback completar → descarga URL | Suite de humo GREEN |

---

## Capa de Dominio

### Entidades

#### `ReportRequest`

```java
// src/main/java/com/controlstock/reporting/domain/model/ReportRequest.java
public class ReportRequest {
    private final ReportRequestId id;
    private final UsuarioId usuarioId;
    private final ReportType reportType;
    private final Map<String, Object> parametros;   // nullable — filtros de fecha, etc.
    private final FormatoReporte formato;            // XLSX | CSV | PDF
    private EstadoReporte estado;
    private final Instant createdAt;
    private Instant updatedAt;

    public static ReportRequest crear(
            UsuarioId usuarioId,
            ReportType reportType,
            Map<String, Object> parametros,
            FormatoReporte formato) {
        return new ReportRequest(
            new ReportRequestId(UUID.randomUUID()),
            usuarioId, reportType, parametros, formato,
            EstadoReporte.SOLICITADO,
            Instant.now(), Instant.now()
        );
    }

    /**
     * Transición: SOLICITADO → PROCESANDO.
     * Se activa cuando el ETL confirma recepción del evento Kafka.
     */
    public void marcarProcesando() {
        if (this.estado != EstadoReporte.SOLICITADO) {
            throw new TransicionEstadoInvalidaException(
                this.id, this.estado, EstadoReporte.PROCESANDO);
        }
        this.estado = EstadoReporte.PROCESANDO;
        this.updatedAt = Instant.now();
    }

    /**
     * Transición: PROCESANDO → COMPLETADO.
     * Llamado desde el callback REST del report-format-consumer.
     */
    public void marcarCompletado() {
        if (this.estado != EstadoReporte.PROCESANDO &&
            this.estado != EstadoReporte.SOLICITADO) {
            throw new TransicionEstadoInvalidaException(
                this.id, this.estado, EstadoReporte.COMPLETADO);
        }
        this.estado = EstadoReporte.COMPLETADO;
        this.updatedAt = Instant.now();
    }

    /**
     * Transición: cualquier estado → FALLIDO.
     * Se activa al recibir ReporteETLFallido de Kafka o callback /fallar.
     */
    public void marcarFallido() {
        if (this.estado == EstadoReporte.COMPLETADO) {
            throw new TransicionEstadoInvalidaException(
                this.id, this.estado, EstadoReporte.FALLIDO);
        }
        this.estado = EstadoReporte.FALLIDO;
        this.updatedAt = Instant.now();
    }

    /**
     * Invariante de descarga: solo se puede descargar si COMPLETADO.
     */
    public void verificarDescargable() {
        if (this.estado != EstadoReporte.COMPLETADO) {
            throw new ReporteNoCompletadoException(this.id, this.estado);
        }
    }

    public boolean isCompletado() { return EstadoReporte.COMPLETADO == this.estado; }
    // Getters...
}
```

#### `ReportFile`

```java
// src/main/java/com/controlstock/reporting/domain/model/ReportFile.java
public class ReportFile {
    private final ReportFileId id;
    private final ReportRequestId reportRequestId;
    private final FormatoReporte formato;
    private final MinioUrl urlMinio;   // REQUIRED: URL del archivo en MinIO
    private final Long tamanioBytesValue; // nullable
    private final Instant createdAt;

    public static ReportFile crear(
            ReportRequestId reportRequestId,
            FormatoReporte formato,
            MinioUrl urlMinio,
            Long tamanioBytes) {
        Objects.requireNonNull(urlMinio, "url_minio es obligatorio");
        return new ReportFile(
            new ReportFileId(UUID.randomUUID()),
            reportRequestId, formato, urlMinio,
            tamanioBytes, Instant.now()
        );
    }
    // Getters — registro inmutable, no hay setters
}
```

### Value Objects

| Value Object | Validaciones | Clase |
|-------------|-------------|-------|
| `ReportRequestId` | UUID no nulo | `com.controlstock.reporting.domain.vo.ReportRequestId` |
| `ReportFileId` | UUID no nulo | `com.controlstock.reporting.domain.vo.ReportFileId` |
| `UsuarioId` | UUID no nulo | `com.controlstock.reporting.domain.vo.UsuarioId` |
| `ReportType` | No nulo, no vacío, debe existir en `report_schema_catalog` (verificado en use case) | `com.controlstock.reporting.domain.vo.ReportType` |
| `FormatoReporte` | Enum: `XLSX`, `CSV`, `PDF` | `com.controlstock.reporting.domain.vo.FormatoReporte` |
| `EstadoReporte` | Enum: `SOLICITADO`, `PROCESANDO`, `COMPLETADO`, `FALLIDO` | `com.controlstock.reporting.domain.vo.EstadoReporte` |
| `MinioUrl` | No nulo, no vacío, máx 500 chars | `com.controlstock.reporting.domain.vo.MinioUrl` |

```java
// ReportType — debe existir en el catálogo (validado en use case)
public record ReportType(String value) {
    public ReportType {
        Objects.requireNonNull(value, "report_type no puede ser nulo");
        if (value.isBlank()) {
            throw new ReportTypeVacioException();
        }
    }
}

// MinioUrl — URL de referencia al archivo en MinIO (nunca vacío)
public record MinioUrl(String value) {
    public MinioUrl {
        Objects.requireNonNull(value, "url_minio no puede ser nula");
        if (value.isBlank()) {
            throw new MinioUrlVaciaException();
        }
        if (value.length() > 500) {
            throw new MinioUrlDemasiadoLargaException(value.length());
        }
    }
}
```

### Excepciones de Dominio

```java
// Transición de estado inválida
public class TransicionEstadoInvalidaException extends RuntimeException {
    private final UUID reportRequestId;
    private final EstadoReporte estadoActual;
    private final EstadoReporte estadoObjetivo;

    public TransicionEstadoInvalidaException(
            ReportRequestId id, EstadoReporte actual, EstadoReporte objetivo) {
        super(String.format("Transición inválida para ReportRequest %s: %s → %s",
            id.value(), actual, objetivo));
        this.reportRequestId = id.value();
        this.estadoActual = actual;
        this.estadoObjetivo = objetivo;
    }
}

// Descarga solicitada pero el reporte no está COMPLETADO
public class ReporteNoCompletadoException extends RuntimeException {
    private final UUID reportRequestId;
    private final EstadoReporte estadoActual;

    public ReporteNoCompletadoException(ReportRequestId id, EstadoReporte estado) {
        super(String.format(
            "El reporte %s no puede descargarse porque no está COMPLETADO (estado: %s)",
            id.value(), estado));
        this.reportRequestId = id.value();
        this.estadoActual = estado;
    }
}

// Tipo de reporte no existe en el catálogo
public class ReportTypeNoEncontradoException extends RuntimeException {
    public ReportTypeNoEncontradoException(String reportType) {
        super(String.format("El tipo de reporte '%s' no existe en el catálogo", reportType));
    }
}

// ReportRequest no encontrado
public class ReportRequestNoEncontradaException extends RuntimeException {
    public ReportRequestNoEncontradaException(ReportRequestId id) {
        super(String.format("ReportRequest no encontrada: %s", id.value()));
    }
}
```

### Eventos de Dominio (Kafka)

```java
// SolicitudReporteGenerada — publicado directamente a Kafka (no via Outbox)
// Este evento activa el report-etl-service para generar el reporte.
public record SolicitudReporteGenerada(
    UUID reportRequestId,
    UUID usuarioId,
    String reportType,
    Map<String, Object> parametros,
    String formato,
    Instant occurredAt
) implements DomainEvent {
    public SolicitudReporteGenerada(ReportRequest request) {
        this(request.getId().value(),
             request.getUsuarioId().value(),
             request.getReportType().value(),
             request.getParametros(),
             request.getFormato().name(),
             Instant.now());
    }

    @Override public String getEventType()     { return "SolicitudReporteGenerada"; }
    @Override public String getAggregateType() { return "ReportRequest"; }
    @Override public UUID getAggregateId()     { return reportRequestId; }
    @Override public Instant getOccurredAt()   { return occurredAt; }
    @Override public String getTopic() {
        return "controlstock.reporting.requests";
    }
}
```

### Topics de Kafka

| Evento | Topic | Rol | Partitions | Retention |
|--------|-------|-----|-----------|-----------|
| `SolicitudReporteGenerada` | `controlstock.reporting.requests` | Producido | 3 | 7 días |
| `ReporteETLFallido` | `controlstock.reporting.etl-fallido` | Consumido | 3 | 7 días |

### Puertos (Interfaces de Dominio)

```java
// Puerto: ReportRequestRepository (PostgreSQL, R2DBC)
public interface ReportRequestRepository {
    Mono<ReportRequest> save(ReportRequest request);
    Mono<ReportRequest> findById(ReportRequestId id);
    Flux<ReportRequest> findByUsuarioId(UsuarioId usuarioId, Pageable pageable);
    Flux<ReportRequest> findAll(ReportRequestFilter filter, Pageable pageable);
}

// Puerto: ReportFileRepository (PostgreSQL, R2DBC)
public interface ReportFileRepository {
    Mono<ReportFile> save(ReportFile file);
    Mono<ReportFile> findByReportRequestId(ReportRequestId requestId);
}

// Puerto: ReportSchemaCatalogRepository (PostgreSQL, R2DBC — read-only)
public interface ReportSchemaCatalogRepository {
    Mono<Boolean> existsByReportType(ReportType reportType);
    Flux<ReportSchemaCatalog> findAll();
}

// Puerto: KafkaReportPublisher (publicación directa a Kafka)
public interface KafkaReportPublisher {
    Mono<Void> publish(SolicitudReporteGenerada evento);
}

// Puerto: MinioPresignedUrlPort (generación de URL con TTL)
public interface MinioPresignedUrlPort {
    Mono<String> generatePresignedUrl(String minioObjectPath, Duration ttl);
}
```

### Invariantes de Dominio

| Invariante | Regla | Excepción |
|-----------|-------|-----------|
| **Tipo de reporte válido** | `report_type` debe existir en `report_schema_catalog` (verificado en use case) | `ReportTypeNoEncontradoException` |
| **Descarga solo si COMPLETADO** | `GET /reports/{id}/download` lanza error si `estado != COMPLETADO` | `ReporteNoCompletadoException` |
| **Transiciones de estado válidas** | SOLICITADO → PROCESANDO → COMPLETADO; cualquier estado → FALLIDO (excepto COMPLETADO) | `TransicionEstadoInvalidaException` |
| **URL MinIO obligatoria al completar** | `url_minio` no puede ser nulo ni vacío al registrar `ReportFile` | `MinioUrlVaciaException` |

---

## Capa de Aplicación

### Use Cases

#### `SolicitarReporteUseCase`

```java
@Service
@RequiredArgsConstructor
public class SolicitarReporteUseCase {
    private final ReportRequestRepository reportRequestRepository;
    private final ReportSchemaCatalogRepository schemaCatalogRepository;
    private final KafkaReportPublisher kafkaPublisher;
    private final TransactionalOperator transactionalOperator;

    /**
     * Solicita la generación de un nuevo reporte.
     * 1. Valida que el report_type existe en el catálogo.
     * 2. Crea el ReportRequest en estado SOLICITADO.
     * 3. Persiste el request.
     * 4. Publica SolicitudReporteGenerada directamente a Kafka.
     *    (No se usa Outbox: la pérdida de un request de reporte es tolerable;
     *     el usuario puede re-solicitar. Esta decisión reduce la complejidad.)
     * Retorna 202 Accepted con el ID del request.
     */
    public Mono<ReportRequestResponse> ejecutar(SolicitarReporteCommand cmd) {
        return schemaCatalogRepository.existsByReportType(cmd.reportType())
            .flatMap(exists -> {
                if (!exists) {
                    return Mono.error(new ReportTypeNoEncontradoException(
                        cmd.reportType().value()));
                }
                ReportRequest request = ReportRequest.crear(
                    cmd.usuarioId(), cmd.reportType(),
                    cmd.parametros(), cmd.formato()
                );
                return reportRequestRepository.save(request)
                    .flatMap(saved -> {
                        SolicitudReporteGenerada evento = new SolicitudReporteGenerada(saved);
                        return kafkaPublisher.publish(evento)
                            .thenReturn(ReportRequestResponse.from(saved));
                    });
            })
            .as(transactionalOperator::transactional);
    }
}
```

#### `CompletarReporteUseCase`

```java
@Service
@RequiredArgsConstructor
public class CompletarReporteUseCase {
    private final ReportRequestRepository reportRequestRepository;
    private final ReportFileRepository reportFileRepository;
    private final TransactionalOperator transactionalOperator;

    /**
     * Callback interno del report-format-consumer.
     * Marca el ReportRequest como COMPLETADO y registra el ReportFile con la URL MinIO.
     * Idempotente: si ya está COMPLETADO, retorna sin error.
     */
    public Mono<ReportRequestResponse> ejecutar(CompletarReporteCommand cmd) {
        return reportRequestRepository.findById(cmd.reportRequestId())
            .switchIfEmpty(Mono.error(
                new ReportRequestNoEncontradaException(cmd.reportRequestId())))
            .flatMap(request -> {
                if (request.isCompletado()) {
                    // Idempotente: ya completado previamente
                    return reportRequestRepository.save(request)
                        .thenReturn(ReportRequestResponse.from(request));
                }
                request.marcarCompletado();
                ReportFile file = ReportFile.crear(
                    request.getId(), cmd.formato(),
                    cmd.urlMinio(), cmd.tamanioBytes()
                );
                return reportRequestRepository.save(request)
                    .then(reportFileRepository.save(file))
                    .thenReturn(ReportRequestResponse.from(request));
            })
            .as(transactionalOperator::transactional);
    }
}
```

#### `FallarReporteUseCase`

```java
@Service
@RequiredArgsConstructor
public class FallarReporteUseCase {
    private final ReportRequestRepository reportRequestRepository;
    private final TransactionalOperator transactionalOperator;

    /**
     * Marca un ReportRequest como FALLIDO.
     * Invocado por:
     *  - Kafka consumer al recibir ReporteETLFallido
     *  - Callback REST POST /reports/{id}/fallar del report-format-consumer
     */
    public Mono<Void> ejecutar(ReportRequestId reportRequestId) {
        return reportRequestRepository.findById(reportRequestId)
            .switchIfEmpty(Mono.error(
                new ReportRequestNoEncontradaException(reportRequestId)))
            .flatMap(request -> {
                request.marcarFallido();
                return reportRequestRepository.save(request).then();
            })
            .as(transactionalOperator::transactional);
    }
}
```

#### `DescargarReporteUseCase`

```java
@Service
@RequiredArgsConstructor
public class DescargarReporteUseCase {
    private final ReportRequestRepository reportRequestRepository;
    private final ReportFileRepository reportFileRepository;
    private final MinioPresignedUrlPort minioPresignedUrlPort;

    /**
     * Genera una URL pre-firmada de MinIO con TTL de 15 minutos.
     * Solo disponible si el estado es COMPLETADO.
     */
    public Mono<String> ejecutar(ReportRequestId requestId, UsuarioId requestingUser) {
        return reportRequestRepository.findById(requestId)
            .switchIfEmpty(Mono.error(
                new ReportRequestNoEncontradaException(requestId)))
            .flatMap(request -> {
                // Lanza ReporteNoCompletadoException si no está COMPLETADO
                request.verificarDescargable();
                return reportFileRepository.findByReportRequestId(request.getId());
            })
            .flatMap(file ->
                minioPresignedUrlPort.generatePresignedUrl(
                    file.getUrlMinio().value(),
                    Duration.ofMinutes(15)
                )
            );
    }
}
```

### DTOs

```java
// Command: SolicitarReporteCommand
public record SolicitarReporteCommand(
    UsuarioId usuarioId,
    ReportType reportType,
    Map<String, Object> parametros,   // nullable
    FormatoReporte formato
) {}

// Command: CompletarReporteCommand
public record CompletarReporteCommand(
    ReportRequestId reportRequestId,
    FormatoReporte formato,
    MinioUrl urlMinio,
    Long tamanioBytes          // nullable
) {}

// Response: ReportRequestResponse
public record ReportRequestResponse(
    UUID id,
    UUID usuarioId,
    String reportType,
    Map<String, Object> parametros,
    String formato,
    String estado,
    Instant createdAt,
    Instant updatedAt
) {
    public static ReportRequestResponse from(ReportRequest request) { /* ... */ }
}
```

---

## Capa de Infraestructura

### R2DBC — `ReportRequestR2dbcAdapter`

```java
@Repository
@RequiredArgsConstructor
public class ReportRequestR2dbcAdapter implements ReportRequestRepository {
    private final ReportRequestR2dbcRepo r2dbcRepo;

    @Override
    public Mono<ReportRequest> save(ReportRequest request) {
        return r2dbcRepo.save(ReportRequestMapper.toEntity(request))
            .map(ReportRequestMapper::toDomain);
    }

    @Override
    public Mono<ReportRequest> findById(ReportRequestId id) {
        return r2dbcRepo.findById(id.value())
            .map(ReportRequestMapper::toDomain);
    }

    @Override
    public Flux<ReportRequest> findByUsuarioId(UsuarioId usuarioId, Pageable pageable) {
        return r2dbcRepo.findByUsuarioId(usuarioId.value(), pageable)
            .map(ReportRequestMapper::toDomain);
    }

    @Override
    public Flux<ReportRequest> findAll(ReportRequestFilter filter, Pageable pageable) {
        return r2dbcRepo.findByFilter(
            filter.usuarioId() != null ? filter.usuarioId().value() : null,
            filter.estado() != null ? filter.estado().name() : null,
            pageable
        ).map(ReportRequestMapper::toDomain);
    }
}

// Spring Data R2DBC entity
@Table("report_requests")
public class ReportRequestEntity {
    @Id private UUID id;
    private UUID usuarioId;
    private String reportType;
    @Column("parametros")
    private String parametrosJson;  // JSONB serializado
    private String formato;
    private String estado;
    private Instant createdAt;
    private Instant updatedAt;
}
```

### Kafka — Productor (`SolicitudReporteGenerada`)

```java
@Component
@RequiredArgsConstructor
@Slf4j
public class KafkaReportPublisherAdapter implements KafkaReportPublisher {
    private final ReactiveKafkaProducerTemplate<String, String> kafkaTemplate;
    private final ObjectMapper objectMapper;

    @Override
    public Mono<Void> publish(SolicitudReporteGenerada evento) {
        return Mono.fromCallable(() -> objectMapper.writeValueAsString(evento))
            .flatMap(payload ->
                kafkaTemplate.send(
                    evento.getTopic(),
                    evento.getReportRequestId().toString(),
                    payload
                )
            )
            .doOnNext(result -> log.info("SolicitudReporteGenerada publicada: reportRequestId={}, offset={}",
                evento.getReportRequestId(), result.recordMetadata().offset()))
            .then();
    }
}
```

### Kafka — Consumidor (`ReporteETLFallido`)

```java
@Component
@RequiredArgsConstructor
@Slf4j
public class ReporteETLFallidoConsumer {
    private final ReactiveKafkaConsumerTemplate<String, String> consumerTemplate;
    private final FallarReporteUseCase fallarReporteUseCase;
    private final ObjectMapper objectMapper;

    /**
     * Consume ReporteETLFallido y marca el ReportRequest como FALLIDO.
     * Consumer group: controlstock-report-service-consumer
     */
    @PostConstruct
    public void startConsumer() {
        consumerTemplate.receiveAutoAck()
            .flatMap(record -> {
                try {
                    ReporteETLFallidoPayload payload =
                        objectMapper.readValue(record.value(), ReporteETLFallidoPayload.class);
                    return fallarReporteUseCase.ejecutar(
                        new ReportRequestId(payload.reportRequestId())
                    ).onErrorResume(e -> {
                        log.error("Error al marcar reporte fallido: reportRequestId={}",
                            payload.reportRequestId(), e);
                        return Mono.empty();
                    });
                } catch (Exception e) {
                    log.error("Error deserializando ReporteETLFallido", e);
                    return Mono.empty();
                }
            })
            .subscribe();
    }
}

// Payload deserializado del evento Kafka
public record ReporteETLFallidoPayload(
    UUID reportRequestId,
    String motivo,
    Instant occurredAt
) {}
```

### MinIO — `MinioPresignedUrlAdapter`

```java
@Component
@RequiredArgsConstructor
@Slf4j
public class MinioPresignedUrlAdapter implements MinioPresignedUrlPort {
    private final MinioAsyncClient minioClient;

    @Value("${minio.bucket-name:controlstock-reports}")
    private String bucketName;

    /**
     * Genera una URL pre-firmada de MinIO con el TTL especificado.
     * La URL permite descarga directa sin autenticación adicional
     * durante el período de validez (15 minutos por defecto).
     */
    @Override
    public Mono<String> generatePresignedUrl(String minioObjectPath, Duration ttl) {
        return Mono.fromFuture(
            minioClient.getPresignedObjectUrl(
                GetPresignedObjectUrlArgs.builder()
                    .method(Method.GET)
                    .bucket(bucketName)
                    .object(minioObjectPath)
                    .expiry((int) ttl.getSeconds(), TimeUnit.SECONDS)
                    .build()
            )
        ).doOnNext(url -> log.debug("Pre-signed URL generada para objeto={}: ttl={}s",
            minioObjectPath, ttl.getSeconds()));
    }
}
```

### Spring Security

```yaml
# application.yml — security config
spring:
  security:
    oauth2:
      resourceserver:
        jwt:
          issuer-uri: http://keycloak.apps.svc.cluster.local:8080/realms/controlstock
          jwk-set-uri: http://keycloak.apps.svc.cluster.local:8080/realms/controlstock/protocol/openid-connect/certs

minio:
  endpoint: http://minio.minio.svc.cluster.local:9000
  bucket-name: controlstock-reports
```

```java
@Configuration
@EnableWebFluxSecurity
public class SecurityConfig {
    @Bean
    public SecurityWebFilterChain springSecurityFilterChain(ServerHttpSecurity http) {
        return http
            .authorizeExchange(exchanges -> exchanges
                .pathMatchers("/actuator/**").permitAll()
                // Callback interno del report-format-consumer — requiere rol SYSTEM
                .pathMatchers(HttpMethod.POST, "/reports/{id}/completar",
                                              "/reports/{id}/fallar")
                    .hasRole("SYSTEM")
                // Endpoints de usuario final
                .pathMatchers(HttpMethod.POST, "/reports")
                    .hasAnyRole("GERENTE", "ANALISTA", "AUDITOR", "ADMINISTRADOR")
                .pathMatchers(HttpMethod.GET, "/reports", "/reports/**")
                    .hasAnyRole("GERENTE", "ANALISTA", "AUDITOR", "ADMINISTRADOR")
                .anyExchange().authenticated()
            )
            .oauth2ResourceServer(oauth2 -> oauth2.jwt(Customizer.withDefaults()))
            .csrf(ServerHttpSecurity.CsrfSpec::disable)
            .build();
    }
}
```

---

## API REST

### Endpoints

| Método | Ruta | Descripción | Rol requerido | Código éxito |
|--------|------|-------------|---------------|-------------|
| `GET` | `/reports` | Listar solicitudes (usuario ve solo las suyas; Gerente/Auditor ven todas). Filtros: `estado`, paginado | Gerente, Analista, Auditor, Admin | 200 |
| `POST` | `/reports` | Solicitar generación de reporte | Gerente, Analista, Auditor, Admin | 202 |
| `GET` | `/reports/{id}` | Consultar estado de una solicitud | Gerente, Analista, Auditor, Admin | 200 |
| `GET` | `/reports/{id}/download` | Obtener URL de descarga pre-firmada (solo si COMPLETADO) | Gerente, Analista, Auditor, Admin | 302 / 200 |
| `POST` | `/reports/{id}/completar` | Callback interno: marcar COMPLETADO y registrar URL MinIO | SYSTEM | 200 |
| `POST` | `/reports/{id}/fallar` | Callback interno: marcar FALLIDO | SYSTEM | 200 |

### Contratos de Request/Response

```json
// POST /reports — solicitar reporte
// Request
{
  "reportType": "movimientos-periodo",
  "formato": "XLSX",
  "parametros": {
    "desde": "2025-01-01",
    "hasta": "2025-01-31",
    "almacenId": "uuid-opcional"
  }
}
// Response 202 Accepted
{
  "id": "uuid",
  "reportType": "movimientos-periodo",
  "formato": "XLSX",
  "estado": "SOLICITADO",
  "usuarioId": "uuid",
  "createdAt": "2025-01-15T10:00:00Z",
  "updatedAt": "2025-01-15T10:00:00Z"
}

// POST /reports — tipo inválido
// Response 404
{
  "error": "REPORT_TYPE_NO_ENCONTRADO",
  "mensaje": "El tipo de reporte 'tipo-invalido' no existe en el catálogo"
}

// GET /reports/{id}/download — reporte no COMPLETADO
// Response 409
{
  "error": "REPORTE_NO_COMPLETADO",
  "mensaje": "El reporte no puede descargarse porque no está COMPLETADO (estado: PROCESANDO)",
  "reportRequestId": "uuid",
  "estadoActual": "PROCESANDO"
}

// GET /reports/{id}/download — reporte COMPLETADO
// Response 302 Redirect o Response 200
{
  "downloadUrl": "https://<VPS_IP>:9000/controlstock-reports/reporte-uuid.xlsx?X-Amz-Expires=900&...",
  "expiresInSeconds": 900
}

// POST /reports/{id}/completar — callback del format-consumer
// Request
{
  "formato": "XLSX",
  "urlMinio": "reportes/2025/01/movimientos-periodo-uuid.xlsx",
  "tamanioBytes": 204800
}
// Response 200
{
  "id": "uuid",
  "estado": "COMPLETADO",
  "updatedAt": "2025-01-15T10:05:00Z"
}

// POST /reports/{id}/fallar — callback del format-consumer o ETL
// Response 200
{
  "id": "uuid",
  "estado": "FALLIDO",
  "updatedAt": "2025-01-15T10:05:00Z"
}
```

### `@ExceptionHandler` en `GlobalExceptionHandler`

| Excepción | HTTP Status | Campo en body |
|-----------|-------------|---------------|
| `ReportRequestNoEncontradaException` | 404 | `reportRequestId` |
| `ReportTypeNoEncontradoException` | 404 | `error: REPORT_TYPE_NO_ENCONTRADO` |
| `ReporteNoCompletadoException` | 409 | `reportRequestId`, `estadoActual` |
| `TransicionEstadoInvalidaException` | 409 | `reportRequestId`, `estadoActual`, `estadoObjetivo` |
| `MinioUrlVaciaException` | 400 | `error: MINIO_URL_VACIA` |
| `WebExchangeBindException` | 400 | errores de validación Bean Validation |

---

## Especificación TDD por Capa (Red-Green-Refactor)

### Filosofía TDD Aplicada

```
RED   → Escribir test que falla (la funcionalidad NO existe aún)
GREEN → Implementar el mínimo código para que el test pase
REFACTOR → Mejorar diseño sin romper tests existentes

Reglas reactivas obligatorias:
- NUNCA usar block() en tests ni en producción
- StepVerifier para TODOS los Mono/Flux
- Testcontainers para tests de infraestructura real
```

### Capa de Dominio

| # | Test Class | Caso de prueba | Aserción |
|---|-----------|----------------|----------|
| D-01 | `ReportRequestTest` | `crear_conDatosValidos_estadoSolicitado` | `estado == SOLICITADO`; `reportType` preservado |
| D-02 | `ReportRequestTest` | `marcarProcesando_desdeSolicitado_transicionValida` | `estado == PROCESANDO` |
| D-03 | `ReportRequestTest` | `marcarProcesando_desdeProcesando_lanzaExcepcion` | `TransicionEstadoInvalidaException` |
| D-04 | `ReportRequestTest` | `marcarCompletado_desdeProcesando_transicionValida` | `estado == COMPLETADO` |
| D-05 | `ReportRequestTest` | `marcarCompletado_desdeFallido_lanzaExcepcion` | `TransicionEstadoInvalidaException` |
| D-06 | `ReportRequestTest` | `marcarFallido_desdeAnyEstadoExceptoCompletado_transicionValida` | `estado == FALLIDO` |
| D-07 | `ReportRequestTest` | `marcarFallido_desdeCompletado_lanzaExcepcion` | `TransicionEstadoInvalidaException` |
| D-08 | `ReportRequestTest` | `verificarDescargable_estadoCompletado_noLanzaExcepcion` | Sin excepción |
| D-09 | `ReportRequestTest` | `verificarDescargable_estadoProcesando_lanzaExcepcion` | `ReporteNoCompletadoException` |
| D-10 | `ReportFileTest` | `crear_conUrlMinioVacia_lanzaExcepcion` | `MinioUrlVaciaException` |
| D-11 | `ReportFileTest` | `crear_conUrlMinioValida_construyeExitosamente` | `urlMinio.value()` preservado |
| D-12 | `ReportTypeTest` | `reportTypeVacio_lanzaExcepcion` | `ReportTypeVacioException` |

**Cobertura objetivo: dominio >= 90%**

### Capa de Aplicación

| # | Test Class | Caso de prueba | Mock / Aserción |
|---|-----------|----------------|-----------------|
| A-01 | `SolicitarReporteUseCaseTest` | `ejecutar_tipoValido_creaRequestYPublicaKafka` | `kafkaPublisher.publish(SolicitudReporteGenerada)` llamado; `StepVerifier` verifica 202 response con `estado: SOLICITADO` |
| A-02 | `SolicitarReporteUseCaseTest` | `ejecutar_tipoInvalido_lanzaExcepcion` | `expectError(ReportTypeNoEncontradoException.class)`; `reportRequestRepository.save(...)` NO llamado |
| A-03 | `CompletarReporteUseCaseTest` | `ejecutar_requestExistente_marcaCompletadoYGuardaFile` | `reportFileRepository.save(ReportFile)` llamado; `estado == COMPLETADO` |
| A-04 | `CompletarReporteUseCaseTest` | `ejecutar_requestYaCompletado_idempotente` | Retorna sin error; `reportFileRepository.save(...)` NO llamado en segunda invocación |
| A-05 | `CompletarReporteUseCaseTest` | `ejecutar_requestNoExiste_lanzaExcepcion` | `expectError(ReportRequestNoEncontradaException.class)` |
| A-06 | `FallarReporteUseCaseTest` | `ejecutar_requestEnProcesando_marcaFallido` | `reportRequestRepository.save(...)` llamado con `estado: FALLIDO` |
| A-07 | `FallarReporteUseCaseTest` | `ejecutar_requestCompletado_lanzaExcepcion` | `expectError(TransicionEstadoInvalidaException.class)` |
| A-08 | `DescargarReporteUseCaseTest` | `ejecutar_requestCompletado_retornaPresignedUrl` | `minioPresignedUrlPort.generatePresignedUrl(...)` llamado con TTL 15 min; URL retornada |
| A-09 | `DescargarReporteUseCaseTest` | `ejecutar_requestNoCcompletado_lanzaExcepcion` | `expectError(ReporteNoCompletadoException.class)` |

**Cobertura objetivo: aplicación >= 85%**

### Capa de Infraestructura

| # | Test Class | Tipo | Caso de prueba |
|---|-----------|------|----------------|
| I-01 | `ReportRequestR2dbcAdapterTest` | `@DataR2dbcTest` + Testcontainers PG | `save_findById_roundtrip_preservaDatosYEstado` |
| I-02 | `ReportRequestR2dbcAdapterTest` | `@DataR2dbcTest` + Testcontainers PG | `findByUsuarioId_retornaSoloReportesDelUsuario` |
| I-03 | `ReportFileR2dbcAdapterTest` | `@DataR2dbcTest` + Testcontainers PG | `save_findByReportRequestId_roundtrip_preservaUrlMinio` |
| I-04 | `ReportSchemaCatalogAdapterTest` | `@DataR2dbcTest` + Testcontainers PG (seeds) | `existsByReportType_tipoConocido_retornaTrue` |
| I-05 | `ReportSchemaCatalogAdapterTest` | `@DataR2dbcTest` + Testcontainers PG | `existsByReportType_tipoDesconocido_retornaFalse` |
| I-06 | `KafkaReportPublisherAdapterTest` | `@SpringBootTest` + Testcontainers Kafka | `publish_solicitudReporteGenerada_en_topicRequests` |
| I-07 | `ReporteETLFallidoConsumerTest` | `@SpringBootTest` + Testcontainers PG + Kafka | `consumer_recibeReporteETLFallido_marcaRequestFallido` |
| I-08 | `MinioPresignedUrlAdapterTest` | Unit test con MinioAsyncClient mock | `generatePresignedUrl_ttl15min_retornaUrlValida` |

**Cobertura objetivo: infraestructura >= 80%**

### API REST

| # | Test Class | Tipo | Caso de prueba |
|---|-----------|------|----------------|
| R-01 | `ReportControllerTest` | `@WebFluxTest` | `POST /reports con tipo válido → 202 con estado SOLICITADO` |
| R-02 | `ReportControllerTest` | `@WebFluxTest` | `POST /reports con tipo inválido → 404` |
| R-03 | `ReportControllerTest` | `@WebFluxTest` | `POST /reports con rol no autorizado (OPERADOR) → 403` |
| R-04 | `ReportControllerTest` | `@WebFluxTest` | `GET /reports/{id} reporte existente → 200 con estado` |
| R-05 | `ReportControllerTest` | `@WebFluxTest` | `GET /reports/{id} no existe → 404` |
| R-06 | `ReportControllerTest` | `@WebFluxTest` | `GET /reports/{id}/download reporte COMPLETADO → 200 con downloadUrl` |
| R-07 | `ReportControllerTest` | `@WebFluxTest` | `GET /reports/{id}/download reporte no COMPLETADO → 409` |
| R-08 | `ReportControllerTest` | `@WebFluxTest` | `POST /reports/{id}/completar con rol SYSTEM → 200` |
| R-09 | `ReportControllerTest` | `@WebFluxTest` | `POST /reports/{id}/completar con rol usuario final → 403` |
| R-10 | `ReportControllerTest` | `@WebFluxTest` | `POST /reports/{id}/completar segunda llamada → 200 (idempotente)` |
| R-11 | `ReportControllerTest` | `@WebFluxTest` | `POST /reports/{id}/fallar con rol SYSTEM → 200` |
| R-12 | `ReportControllerTest` | `@WebFluxTest` | `GET /reports sin token → 401` |

### Configuración Testcontainers

```java
// src/test/java/com/controlstock/reporting/infrastructure/BaseIntegrationTest.java
@Testcontainers
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
public abstract class BaseIntegrationTest {

    @Container
    static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:16-alpine")
        .withDatabaseName("controlstock_reporting_test")
        .withInitScript("db/schema-reporting.sql");  // incluye seeds del catálogo

    @Container
    static KafkaContainer kafka = new KafkaContainer(
        DockerImageName.parse("confluentinc/cp-kafka:7.6.0"));

    @DynamicPropertySource
    static void configureProperties(DynamicPropertyRegistry registry) {
        registry.add("spring.r2dbc.url",
            () -> "r2dbc:postgresql://" + postgres.getHost() + ":" +
                  postgres.getFirstMappedPort() + "/controlstock_reporting_test");
        registry.add("spring.r2dbc.username", postgres::getUsername);
        registry.add("spring.r2dbc.password", postgres::getPassword);
        registry.add("spring.kafka.bootstrap-servers", kafka::getBootstrapServers);
        // MinIO adapter mockeado en tests de infraestructura de API
        registry.add("minio.endpoint", () -> "http://localhost:9000");
    }
}
```

---

## Criterios de Aceptación

| # | Criterio | Verificación |
|---|---------|-------------|
| AC-01 | `POST /reports` con `report_type` válido devuelve **HTTP 202** con `estado: SOLICITADO`; evento `SolicitudReporteGenerada` publicado en topic `controlstock.reporting.requests` | Test A-01, R-01 + consumer Kafka |
| AC-02 | `POST /reports` con `report_type` inexistente en `report_schema_catalog` devuelve **HTTP 404** con `error: REPORT_TYPE_NO_ENCONTRADO` | Test A-02, R-02 |
| AC-03 | `GET /reports/{id}/download` devuelve pre-signed URL con TTL de 15 minutos; solo disponible si `estado == COMPLETADO` | Test A-08, R-06; verificación manual de expiración URL |
| AC-04 | `GET /reports/{id}/download` sobre reporte no-COMPLETADO devuelve **HTTP 409** con `estadoActual` en body | Test A-09, R-07 |
| AC-05 | `POST /reports/{id}/completar` es **idempotente**: segunda llamada retorna 200 sin duplicar `ReportFile` | Test A-04, R-10 |
| AC-06 | Al recibir `ReporteETLFallido` de Kafka, el `ReportRequest` correspondiente cambia a `estado: FALLIDO` | Test I-07 + verificación en K3s con Kafka consumer |
| AC-07 | Roles `OPERADOR` y no autenticados reciben **HTTP 403/401** en todos los endpoints de reporting | Test R-03, R-12 |
| AC-08 | `POST /reports/{id}/completar` solo es accesible con rol `SYSTEM`; roles de usuario final reciben **HTTP 403** | Test R-09 |
| AC-09 | Cobertura: Dominio >= 90%, Aplicación >= 85%, Infraestructura >= 80% | JaCoCo en pipeline Jenkins |
| AC-10 | `GET /actuator/health/readiness` retorna `{ "status": "UP" }` con PostgreSQL y Kafka como health indicators | Verificación manual en K3s |
| AC-11 | Toda la cadena reactiva usa `StepVerifier`; ausencia de `block()` verificada con `BlockHound` | BlockHound activo en `@SpringBootTest` |
