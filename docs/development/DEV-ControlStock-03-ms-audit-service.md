# Etapa 3h — Microservicio: Audit Service (BC-08)

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

El **Audit Service** (Bounded Context BC-08) es el microservicio responsable del registro de auditoría centralizado en ControlStock. Es el **octavo microservicio en implementarse**. Consume eventos de dominio de todos los bounded contexts del sistema, persiste cada operación como registro de auditoría inmutable (append-only) y expone una API de consulta para usuarios autorizados (Auditor / Administrador).

Este servicio tiene la arquitectura más simple del sistema en cuanto a modelo de dominio, pero la mayor complejidad en infraestructura: múltiples consumidores Kafka que cubren todos los topics del sistema, escritura append-only estricta y necesidad de idempotencia en el procesamiento de mensajes.

### Responsabilidades del servicio

| Responsabilidad | Descripción |
|----------------|-------------|
| **Consumo de todos los eventos de dominio** | Subscripción a múltiples topics Kafka del sistema mediante un único consumer group |
| **Persistencia append-only** | Cada evento crea un nuevo `AuditRecord`; nunca se actualiza ni elimina ningún registro |
| **Derivación de operación** | El tipo de operación (`CREAR`, `MODIFICAR`, `INACTIVAR`, etc.) se deriva del tipo de evento de dominio |
| **Idempotencia de consumo** | Prevención de registros duplicados en caso de reentrega Kafka via verificación de `evento_origen + entidad_id` |
| **API de consulta de auditoría** | Endpoint `GET /audit` con filtros: `entidad`, `entidad_id`, `usuario_id`, `desde`, `hasta`, `operacion`; paginado |

### Lo que el servicio NO hace

| Restricción | Justificación |
|-------------|---------------|
| No escribe a `audit_log` via REST | La única fuente de escritura es el consumer Kafka; no hay endpoints de escritura |
| No actualiza ni elimina registros | Append-only es un invariante de sistema; toda modificación directa de `audit_log` es un defecto |
| No participa en sagas | No hay flujos distribuidos que requieran compensación en el log de auditoría |
| No llama a otros servicios via REST | No tiene dependencias de runtime con ningún otro microservicio del sistema |
| No tiene tabla outbox | No produce eventos Kafka; es consumidor puro |
| No proyecta a MongoDB | El almacén de auditoría es PostgreSQL; no requiere proyección de lectura |

### Bounded Context BC-08

```
┌──────────────────────────────────────────────────────────────────────┐
│                    Audit Service (BC-08)                             │
│                                                                      │
│  ┌──────────────────────────────────────────────────────────────┐    │
│  │  Kafka Multi-Topic Consumer                                  │    │
│  │  Consumer Group: controlstock-audit-consumer                 │    │
│  │                                                              │    │
│  │  controlstock.catalog.*    → CREAR / MODIFICAR / INACTIVAR  │    │
│  │  controlstock.inventory.*  → CREAR / MODIFICAR              │    │
│  │  controlstock.adjustment.* → CREAR / MODIFICAR              │    │
│  │  controlstock.supplier.*   → CREAR / MODIFICAR              │    │
│  │  controlstock.integration.*→ CREAR (saga events)            │    │
│  └──────────────────────────────┬───────────────────────────────┘    │
│                                 │                                    │
│          ┌──────────────────────▼───────────────────────────────┐    │
│          │  Idempotencia: check evento_origen + entidad_id       │    │
│          │  → si ya existe en audit_log, descartar silencioso    │    │
│          └──────────────────────┬───────────────────────────────┘    │
│                                 │                                    │
│                                 ▼                                    │
│                    ┌────────────────────────┐                        │
│                    │       audit_log         │                       │
│                    │  - entidad, entidad_id  │                       │
│                    │  - operacion            │                       │
│                    │  - usuario_id           │                       │
│                    │  - timestamp_utc        │                       │
│                    │  - valor_anterior (JSONB)│                      │
│                    │  - valor_posterior(JSONB)│                      │
│                    │  - contexto (JSONB)     │                       │
│                    │  - evento_origen        │                       │
│                    └───────────┬────────────┘                        │
│                                │                                     │
│                    ┌───────────▼────────────┐                        │
│                    │  REST Read API          │                       │
│                    │  GET /audit             │                       │
│                    │  (Auditor / Admin only) │                       │
│                    └────────────────────────┘                        │
└──────────────────────────────────────────────────────────────────────┘
```

### Base de datos

- **PostgreSQL 16** — schema `controlstock_audit` (solo tabla `audit_log`)
- **Tecnología de acceso**: Spring Data R2DBC (reactivo, escritura append-only)
- **No hay MongoDB, no hay outbox**

---

## Prerrequisitos

| Prerrequisito | Documento de referencia | Verificación |
|--------------|------------------------|-------------|
| Etapa 0 — Infraestructura base completa | `DEV-ControlStock-00-infrastructure.md` | K3s corriendo, namespaces activos |
| Etapa 0c — Observabilidad configurada | `DEV-ControlStock-0c-observability.md` | Prometheus + Grafana activos |
| Etapa 1 — Bases de datos aprovisionadas | `DEV-ControlStock-01-databases.md` | PostgreSQL schema `controlstock_audit` con tabla `audit_log` e índices |
| Etapa 2 — Scaffold generado | `DEV-ControlStock-02-scaffold.md` | Proyecto Maven `audit-service` generado |
| Etapa 2b — Pipeline CI/CD configurado | `DEV-ControlStack-02b-cicd.md` | Job `audit-service` activo en Jenkins |
| **Etapa 3a — IAM Service corriendo** | `DEV-ControlStock-03-ms-iam-service.md` | Keycloak emitiendo tokens JWT con roles `AUDITOR`, `ADMIN` |
| Kafka (Strimzi KRaft) corriendo | Etapa 0 | Todos los topics de `controlstock.*` creados |
| **Al menos catalog-service e inventory-service corriendo** | `DEV-ControlStock-03-ms-catalog-service.md`, `DEV-ControlStock-03-ms-inventory-service.md` | Topics `controlstock.catalog.*` y `controlstock.inventory.*` con eventos reales en K3s |

> **Nota de orden de implementación**: El `audit-service` puede implementarse técnicamente en cualquier momento ya que solo consume. Sin embargo, para verificar que los consumidores procesan eventos reales, se recomienda implementarlo después de `inventory-service` (BC-03), que es el servicio más activo en cuanto a publicación de eventos.

### Verificación de prerrequisitos

```bash
# Verificar schema PostgreSQL audit e índices
kubectl exec -n databases deploy/postgresql -- psql \
  -U controlstock_audit -d controlstock_audit \
  -c "\dt" | grep "audit_log"

kubectl exec -n databases deploy/postgresql -- psql \
  -U controlstock_audit -d controlstock_audit \
  -c "\di" | grep "audit_log"
# Salida esperada:
# idx_audit_entidad_id
# idx_audit_usuario_id
# idx_audit_timestamp_desc
# idx_audit_entidad_timestamp

# Verificar todos los topics disponibles en Kafka
kubectl exec -n kafka deploy/kafka -- \
  kafka-topics.sh --list --bootstrap-server kafka:9092 \
  | grep "controlstock\." | sort

# Verificar que catalog-service está publicando eventos
kubectl exec -n kafka deploy/kafka -- \
  kafka-console-consumer.sh \
  --bootstrap-server kafka:9092 \
  --topic controlstock.catalog.producto-creado \
  --from-beginning --max-messages 1

# Verificar token Auditor
TOKEN=$(curl -s -X POST \
  "http://<VPS_IP>:8180/realms/controlstock/protocol/openid-connect/token" \
  -d "client_id=test-client&grant_type=password&username=auditor@test.com&password=test" \
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
│  - Contexto Spring arranca                           │
│  - Consumer Kafka conectado a broker                 │
│  - GET /actuator/health/readiness → 200              │
└──────────────────────────────────────────────────────┘
```

### Orden de implementación incremental

| Incremento | Capa | Contenido | Condición de avance |
|-----------|------|-----------|-------------------|
| **I-1** | Dominio | Value Object `AuditRecord`; VOs `Entidad`, `EntidadId`, `OperacionAudit`; lógica de derivación de operación desde tipo de evento | Tests dominio GREEN |
| **I-2** | Dominio | Puerto `AuditLogRepository` (append-only: solo `save` y `findByFilter`) | Interface definida; compilación GREEN |
| **I-3** | Aplicación | `RegistrarAuditRecordUseCase` con lógica de idempotencia (check `evento_origen` + `entidad_id`) | Tests aplicación con mocks GREEN |
| **I-4** | Aplicación | `ConsultarAuditLogUseCase` con filtros paginados | Tests filtros GREEN |
| **I-5** | Infraestructura | R2DBC adapter para `audit_log` (INSERT-only, nunca UPDATE/DELETE) | Tests Testcontainers (PostgreSQL) GREEN |
| **I-6** | Infraestructura | Consumer Kafka para `controlstock.catalog.*` (tres topics) | Tests Testcontainers (Kafka + PG) GREEN |
| **I-7** | Infraestructura | Consumer Kafka para `controlstock.inventory.*` | Tests Testcontainers (Kafka + PG) GREEN |
| **I-8** | Infraestructura | Consumer Kafka para `controlstock.adjustment.*` y `controlstock.supplier.*` | Tests Testcontainers (Kafka + PG) GREEN |
| **I-9** | Infraestructura | Consumer Kafka para `controlstock.integration.*` | Tests Testcontainers (Kafka + PG) GREEN |
| **I-10** | API REST | Endpoint `GET /audit` con filtros y paginación + `@ExceptionHandler` | Tests `@WebFluxTest` GREEN |
| **I-11** | Integración | Tests E2E en K3s: evento Kafka de catalog-service → registro en audit_log → consulta via API | Suite de humo GREEN |

---

## Capa de Dominio

### Entidades / Value Objects

El modelo de dominio del `audit-service` es intencionalmente simple: el único agregado es `AuditRecord`, que es inmutable desde su creación (append-only). No hay transiciones de estado ni lógica de negocio compleja. La complejidad está en la capa de infraestructura (múltiples consumidores) y en la regla de idempotencia.

#### `AuditRecord`

```java
// src/main/java/com/controlstock/audit/domain/model/AuditRecord.java
public class AuditRecord {
    private final AuditRecordId id;
    private final Entidad entidad;           // nombre de la entidad, ej: "Producto", "Supplier"
    private final EntidadId entidadId;       // UUID de la entidad afectada
    private final OperacionAudit operacion;  // CREAR, MODIFICAR, INACTIVAR, MOVER, ANULAR, COMPENSAR
    private final UsuarioId usuarioId;       // UUID del usuario que originó el evento
    private final Instant timestampUtc;      // timestamp del evento original (del payload Kafka)
    private final Map<String, Object> valorAnterior;  // nullable — estado antes del evento
    private final Map<String, Object> valorPosterior; // nullable — estado después del evento
    private final Map<String, Object> contexto;       // nullable — datos adicionales de contexto
    private final String eventoOrigen;       // tipo de evento Kafka: "ProductoCreado", "AjusteAprobado", etc.

    /**
     * Factory: crea un AuditRecord desde un evento de dominio consumido desde Kafka.
     * El ID se genera siempre nuevo (UUID); la unicidad lógica se verifica en use case
     * via (eventoOrigen, entidadId).
     */
    public static AuditRecord crear(
            Entidad entidad,
            EntidadId entidadId,
            OperacionAudit operacion,
            UsuarioId usuarioId,
            Instant timestampUtc,
            Map<String, Object> valorAnterior,
            Map<String, Object> valorPosterior,
            Map<String, Object> contexto,
            String eventoOrigen) {
        Objects.requireNonNull(entidad, "entidad no puede ser nula");
        Objects.requireNonNull(entidadId, "entidad_id no puede ser nulo");
        Objects.requireNonNull(operacion, "operacion no puede ser nula");
        Objects.requireNonNull(usuarioId, "usuario_id no puede ser nulo");
        Objects.requireNonNull(timestampUtc, "timestamp_utc no puede ser nulo");
        Objects.requireNonNull(eventoOrigen, "evento_origen no puede ser nulo");
        return new AuditRecord(
            new AuditRecordId(UUID.randomUUID()),
            entidad, entidadId, operacion, usuarioId,
            timestampUtc, valorAnterior, valorPosterior,
            contexto, eventoOrigen
        );
    }
    // Getters — inmutable, sin setters
}
```

### Value Objects

| Value Object | Validaciones | Clase |
|-------------|-------------|-------|
| `AuditRecordId` | UUID no nulo | `com.controlstock.audit.domain.vo.AuditRecordId` |
| `Entidad` | No nulo, no vacío, máx 100 chars | `com.controlstock.audit.domain.vo.Entidad` |
| `EntidadId` | UUID no nulo | `com.controlstock.audit.domain.vo.EntidadId` |
| `UsuarioId` | UUID no nulo | `com.controlstock.audit.domain.vo.UsuarioId` |
| `OperacionAudit` | Enum: `CREAR`, `MODIFICAR`, `INACTIVAR`, `MOVER`, `ANULAR`, `COMPENSAR` | `com.controlstock.audit.domain.vo.OperacionAudit` |

```java
// OperacionAudit con lógica de derivación desde tipo de evento
public enum OperacionAudit {
    CREAR, MODIFICAR, INACTIVAR, MOVER, ANULAR, COMPENSAR;

    /**
     * Deriva la operación de auditoría a partir del tipo de evento de dominio (eventType).
     * Convención de nomenclatura:
     *   - *Creado   → CREAR
     *   - *Actualizado, *Aprobado, *StockActualizado → MODIFICAR
     *   - *Inactivado, *Rechazado                   → INACTIVAR (o MODIFICAR según contexto)
     *   - *Revertido, *Compensado                   → COMPENSAR
     *   - *Movimiento*, *Entrada*, *Salida*          → MOVER
     */
    public static OperacionAudit fromEventType(String eventType) {
        if (eventType == null) return MODIFICAR;
        String lower = eventType.toLowerCase();
        if (lower.endsWith("creado") || lower.endsWith("solicitado")) {
            return CREAR;
        }
        if (lower.endsWith("inactivado")) {
            return INACTIVAR;
        }
        if (lower.endsWith("rechazado")) {
            return MODIFICAR; // rechazo es modificación de estado
        }
        if (lower.endsWith("revertido") || lower.endsWith("compensado")) {
            return COMPENSAR;
        }
        if (lower.contains("entrada") || lower.contains("salida") ||
            lower.contains("movimiento")) {
            return MOVER;
        }
        if (lower.endsWith("actualizado") || lower.endsWith("aprobado") ||
            lower.endsWith("stockactualizado")) {
            return MODIFICAR;
        }
        return MODIFICAR; // fallback seguro
    }
}

// Entidad — nombre de la entidad de negocio
public record Entidad(String value) {
    public Entidad {
        Objects.requireNonNull(value, "entidad no puede ser nula");
        if (value.isBlank()) {
            throw new EntidadVaciaException();
        }
        if (value.length() > 100) {
            throw new EntidadDemasiadoLargaException(value.length());
        }
    }
}
```

### Excepciones de Dominio

```java
// Intento de escritura sobre audit_log (violación del invariante append-only)
public class AuditLogEsAppendOnlyException extends RuntimeException {
    public AuditLogEsAppendOnlyException() {
        super("audit_log es append-only: no se permiten operaciones UPDATE ni DELETE");
    }
}

// Evento duplicado (idempotencia)
public class EventoAuditDuplicadoException extends RuntimeException {
    public EventoAuditDuplicadoException(String eventoOrigen, UUID entidadId) {
        super(String.format(
            "AuditRecord duplicado descartado: eventoOrigen=%s, entidadId=%s",
            eventoOrigen, entidadId));
    }
}
```

### Mapa de Derivación de Eventos a Operaciones

| Topic Kafka | Tipo de Evento | Entidad | Operación |
|------------|---------------|---------|-----------|
| `controlstock.catalog.producto-creado` | `ProductoCreado` | `Producto` | `CREAR` |
| `controlstock.catalog.producto-actualizado` | `ProductoActualizado` | `Producto` | `MODIFICAR` |
| `controlstock.catalog.producto-inactivado` | `ProductoInactivado` | `Producto` | `INACTIVAR` |
| `controlstock.inventory.entradas` | `EntradaInventario` | `Movimiento` | `CREAR` |
| `controlstock.inventory.salidas` | `SalidaInventario` | `Movimiento` | `CREAR` |
| `controlstock.inventory.stock-actualizado` | `StockActualizado` | `StockItem` | `MODIFICAR` |
| `controlstock.adjustment.ajuste-solicitado` | `AjusteSolicitado` | `AdjustmentRequest` | `CREAR` |
| `controlstock.adjustment.ajuste-aprobado` | `AjusteAprobado` | `AdjustmentRequest` | `MODIFICAR` |
| `controlstock.adjustment.ajuste-rechazado` | `AjusteRechazado` | `AdjustmentRequest` | `MODIFICAR` |
| `controlstock.supplier.proveedor-creado` | `ProveedorCreado` | `Supplier` | `CREAR` |
| `controlstock.supplier.proveedor-actualizado` | `ProveedorActualizado` | `Supplier` | `MODIFICAR` |
| `controlstock.integration.solicitud-reposicion-enviada` | `SolicitudReposicionEnviada` | `ReposicionRequest` | `CREAR` |

### Puerto (Interface de Dominio)

```java
// Puerto: AuditLogRepository (PostgreSQL, R2DBC — APPEND-ONLY)
public interface AuditLogRepository {
    /**
     * Persiste un nuevo AuditRecord.
     * SOLO INSERT — nunca UPDATE ni DELETE.
     */
    Mono<AuditRecord> save(AuditRecord record);

    /**
     * Verifica si ya existe un registro con el mismo eventoOrigen y entidadId.
     * Usado para idempotencia en el consumer.
     */
    Mono<Boolean> existsByEventoOrigenAndEntidadId(String eventoOrigen, UUID entidadId);

    /**
     * Consulta el log de auditoría con filtros opcionales.
     * Paginado; ordenado por timestamp_utc DESC.
     */
    Flux<AuditRecord> findByFilter(AuditFilter filter, Pageable pageable);

    /**
     * Cuenta total de registros para un filtro (para paginación).
     */
    Mono<Long> countByFilter(AuditFilter filter);
}
```

### Invariantes de Dominio

| Invariante | Regla | Excepción |
|-----------|-------|-----------|
| **Append-only** | `audit_log` NO admite UPDATE ni DELETE; solo INSERT | `AuditLogEsAppendOnlyException` (jamás debería lanzarse si el código es correcto) |
| **Idempotencia de consumo** | Si ya existe un registro con el mismo `(evento_origen, entidad_id)`, el nuevo mensaje se descarta silenciosamente | Log de DEBUG + retorno `Mono.empty()` |
| **Campos obligatorios** | `entidad`, `entidad_id`, `operacion`, `usuario_id`, `timestamp_utc`, `evento_origen` son siempre requeridos | Validaciones en `AuditRecord.crear()` |
| **Sin credenciales en audit_log** | El campo `contexto` y `valor_anterior/posterior` no deben contener credenciales ni tokens (responsabilidad del publisher) | Regla de diseño |

---

## Capa de Aplicación

### Use Cases

#### `RegistrarAuditRecordUseCase`

```java
@Service
@RequiredArgsConstructor
@Slf4j
public class RegistrarAuditRecordUseCase {
    private final AuditLogRepository auditLogRepository;

    /**
     * Crea y persiste un nuevo AuditRecord a partir de un evento Kafka.
     * Idempotente: si ya existe un registro con (eventoOrigen, entidadId),
     * descarta silenciosamente y retorna Mono.empty().
     *
     * IMPORTANTE: este use case NO usa TransactionalOperator porque
     * audit_log es append-only y no hay compensación posible.
     * La idempotencia es la única garantía necesaria.
     */
    public Mono<Void> ejecutar(RegistrarAuditCommand cmd) {
        return auditLogRepository.existsByEventoOrigenAndEntidadId(
                cmd.eventoOrigen(), cmd.entidadId().value())
            .flatMap(exists -> {
                if (Boolean.TRUE.equals(exists)) {
                    log.debug("Evento duplicado descartado: eventoOrigen={}, entidadId={}",
                        cmd.eventoOrigen(), cmd.entidadId().value());
                    return Mono.<Void>empty();
                }
                AuditRecord record = AuditRecord.crear(
                    cmd.entidad(),
                    cmd.entidadId(),
                    cmd.operacion(),
                    cmd.usuarioId(),
                    cmd.timestampUtc(),
                    cmd.valorAnterior(),
                    cmd.valorPosterior(),
                    cmd.contexto(),
                    cmd.eventoOrigen()
                );
                return auditLogRepository.save(record).then();
            });
    }
}
```

#### `ConsultarAuditLogUseCase`

```java
@Service
@RequiredArgsConstructor
public class ConsultarAuditLogUseCase {
    private final AuditLogRepository auditLogRepository;

    /**
     * Consulta el log de auditoría con filtros opcionales.
     * Solo accesible para roles AUDITOR y ADMIN (verificado en SecurityConfig).
     */
    public Flux<AuditRecordResponse> consultar(AuditFilter filter, Pageable pageable) {
        return auditLogRepository.findByFilter(filter, pageable)
            .map(AuditRecordResponse::from);
    }

    public Mono<Long> contarTotal(AuditFilter filter) {
        return auditLogRepository.countByFilter(filter);
    }
}
```

### DTOs

```java
// Command: RegistrarAuditCommand — construido por el consumer desde el payload Kafka
public record RegistrarAuditCommand(
    Entidad entidad,
    EntidadId entidadId,
    OperacionAudit operacion,
    UsuarioId usuarioId,
    Instant timestampUtc,
    Map<String, Object> valorAnterior,   // nullable
    Map<String, Object> valorPosterior,  // nullable
    Map<String, Object> contexto,        // nullable
    String eventoOrigen                  // tipo de evento, ej: "ProductoCreado"
) {}

// Filter: AuditFilter — todos los campos son opcionales
public record AuditFilter(
    String entidad,          // nullable
    UUID entidadId,          // nullable
    UUID usuarioId,          // nullable
    Instant desde,           // nullable
    Instant hasta,           // nullable
    OperacionAudit operacion // nullable
) {}

// Response: AuditRecordResponse
public record AuditRecordResponse(
    UUID id,
    String entidad,
    UUID entidadId,
    String operacion,
    UUID usuarioId,
    Instant timestampUtc,
    Map<String, Object> valorAnterior,
    Map<String, Object> valorPosterior,
    Map<String, Object> contexto,
    String eventoOrigen
) {
    public static AuditRecordResponse from(AuditRecord record) { /* ... */ }
}
```

---

## Capa de Infraestructura

### Schema PostgreSQL — `audit_log`

```sql
-- Tabla audit_log — append-only, nunca UPDATE ni DELETE
CREATE TABLE audit_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    entidad VARCHAR(100) NOT NULL,
    entidad_id UUID NOT NULL,
    operacion VARCHAR(50) NOT NULL CHECK (
        operacion IN ('CREAR','MODIFICAR','INACTIVAR','MOVER','ANULAR','COMPENSAR')
    ),
    usuario_id UUID NOT NULL,
    timestamp_utc TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    valor_anterior JSONB,
    valor_posterior JSONB,
    contexto JSONB,
    evento_origen VARCHAR(100)
);

-- Índices para las consultas frecuentes de la API de auditoría
CREATE INDEX idx_audit_entidad_id
    ON audit_log(entidad_id);
CREATE INDEX idx_audit_usuario_id
    ON audit_log(usuario_id);
CREATE INDEX idx_audit_timestamp_desc
    ON audit_log(timestamp_utc DESC);
CREATE INDEX idx_audit_entidad_timestamp
    ON audit_log(entidad, timestamp_utc DESC);

-- Índice para idempotencia del consumer
CREATE INDEX idx_audit_evento_origen_entidad_id
    ON audit_log(evento_origen, entidad_id);
```

### R2DBC — `AuditLogR2dbcAdapter`

```java
@Repository
@RequiredArgsConstructor
public class AuditLogR2dbcAdapter implements AuditLogRepository {
    private final AuditLogR2dbcRepo r2dbcRepo;
    private final DatabaseClient databaseClient;

    /**
     * SOLO INSERT. Nunca llama a save() de R2DBC con entidades existentes.
     */
    @Override
    public Mono<AuditRecord> save(AuditRecord record) {
        // Usamos INSERT explícito para garantizar append-only.
        // NO usar r2dbcRepo.save() que podría intentar un UPSERT.
        return databaseClient.sql("""
                INSERT INTO audit_log
                    (id, entidad, entidad_id, operacion, usuario_id,
                     timestamp_utc, valor_anterior, valor_posterior, contexto, evento_origen)
                VALUES
                    (:id, :entidad, :entidadId, :operacion, :usuarioId,
                     :timestampUtc, :valorAnterior::jsonb, :valorPosterior::jsonb,
                     :contexto::jsonb, :eventoOrigen)
                """)
            .bind("id", record.getId().value())
            .bind("entidad", record.getEntidad().value())
            .bind("entidadId", record.getEntidadId().value())
            .bind("operacion", record.getOperacion().name())
            .bind("usuarioId", record.getUsuarioId().value())
            .bind("timestampUtc", record.getTimestampUtc())
            .bind("valorAnterior", serializeToJson(record.getValorAnterior()))
            .bind("valorPosterior", serializeToJson(record.getValorPosterior()))
            .bind("contexto", serializeToJson(record.getContexto()))
            .bind("eventoOrigen", record.getEventoOrigen())
            .fetch().rowsUpdated()
            .thenReturn(record);
    }

    @Override
    public Mono<Boolean> existsByEventoOrigenAndEntidadId(String eventoOrigen, UUID entidadId) {
        return databaseClient.sql("""
                SELECT COUNT(1) FROM audit_log
                WHERE evento_origen = :eventoOrigen AND entidad_id = :entidadId
                """)
            .bind("eventoOrigen", eventoOrigen)
            .bind("entidadId", entidadId)
            .map(row -> row.get(0, Long.class))
            .one()
            .map(count -> count != null && count > 0);
    }

    @Override
    public Flux<AuditRecord> findByFilter(AuditFilter filter, Pageable pageable) {
        // Construcción de query dinámica con criterios opcionales
        StringBuilder sql = new StringBuilder("""
            SELECT * FROM audit_log WHERE 1=1
            """);
        Map<String, Object> params = new HashMap<>();

        if (filter.entidad() != null) {
            sql.append(" AND entidad = :entidad");
            params.put("entidad", filter.entidad());
        }
        if (filter.entidadId() != null) {
            sql.append(" AND entidad_id = :entidadId");
            params.put("entidadId", filter.entidadId());
        }
        if (filter.usuarioId() != null) {
            sql.append(" AND usuario_id = :usuarioId");
            params.put("usuarioId", filter.usuarioId());
        }
        if (filter.desde() != null) {
            sql.append(" AND timestamp_utc >= :desde");
            params.put("desde", filter.desde());
        }
        if (filter.hasta() != null) {
            sql.append(" AND timestamp_utc <= :hasta");
            params.put("hasta", filter.hasta());
        }
        if (filter.operacion() != null) {
            sql.append(" AND operacion = :operacion");
            params.put("operacion", filter.operacion().name());
        }
        sql.append(" ORDER BY timestamp_utc DESC");
        sql.append(" LIMIT :limit OFFSET :offset");
        params.put("limit", pageable.getPageSize());
        params.put("offset", pageable.getOffset());

        DatabaseClient.GenericExecuteSpec spec = databaseClient.sql(sql.toString());
        for (Map.Entry<String, Object> entry : params.entrySet()) {
            spec = spec.bind(entry.getKey(), entry.getValue());
        }
        return spec.map(AuditLogMapper::toDomain).all();
    }

    @Override
    public Mono<Long> countByFilter(AuditFilter filter) {
        // Similar a findByFilter pero SELECT COUNT(1)
        // ...implementación análoga...
        return Mono.just(0L); // placeholder
    }

    private String serializeToJson(Map<String, Object> map) {
        if (map == null || map.isEmpty()) return null;
        try {
            return new ObjectMapper().writeValueAsString(map);
        } catch (Exception e) {
            return null;
        }
    }
}
```

### Kafka — Multi-Topic Consumer

El `audit-service` implementa un único consumer group (`controlstock-audit-consumer`) que se subscribe a múltiples topics. Se usa subscripción por patrón (`Pattern`) para reducir la configuración y garantizar que nuevos topics que sigan el patrón `controlstock.*` sean consumidos automáticamente.

```java
@Component
@RequiredArgsConstructor
@Slf4j
public class AuditKafkaConsumer {
    private final RegistrarAuditRecordUseCase registrarAuditUseCase;
    private final ObjectMapper objectMapper;

    /**
     * Consumer configurado con subscripción por patrón.
     * Consumer group: controlstock-audit-consumer
     * Patrón: controlstock\.(catalog|inventory|adjustment|supplier|integration)\..*
     *
     * Cada mensaje Kafka se convierte a RegistrarAuditCommand usando el
     * AuditEventMapper que extrae campos según el tipo de evento.
     */
    @Bean
    public ReactiveKafkaConsumerTemplate<String, String> auditConsumerTemplate(
            ReactiveKafkaConsumerTemplate.ReactiveKafkaConsumerTemplateSpec spec) {
        return spec
            .consumerProperty(ConsumerConfig.GROUP_ID_CONFIG, "controlstock-audit-consumer")
            .consumerProperty(ConsumerConfig.AUTO_OFFSET_RESET_CONFIG, "earliest")
            .build();
    }

    @PostConstruct
    public void startConsumer() {
        auditConsumerTemplate()
            .receiveAutoAck()
            .flatMap(record -> {
                String topic = record.topic();
                String eventType = extractEventType(record);
                log.debug("Audit consumer recibió evento: topic={}, eventType={}", topic, eventType);
                try {
                    RegistrarAuditCommand cmd = AuditEventMapper.toCommand(
                        topic, eventType, record.value(), objectMapper
                    );
                    return registrarAuditUseCase.ejecutar(cmd)
                        .onErrorResume(e -> {
                            log.error("Error registrando audit record: topic={}, eventType={}",
                                topic, eventType, e);
                            return Mono.empty(); // no propagar error; mensaje ya desencadenado
                        });
                } catch (Exception e) {
                    log.error("Error mapeando evento de auditoría: topic={}", topic, e);
                    return Mono.empty();
                }
            })
            .subscribe();
    }

    private String extractEventType(ConsumerRecord<String, String> record) {
        // Extrae el tipo de evento desde el header Kafka "eventType"
        // o desde el campo "eventType" del payload JSON
        Header header = record.headers().lastHeader("eventType");
        if (header != null) {
            return new String(header.value(), StandardCharsets.UTF_8);
        }
        try {
            JsonNode node = objectMapper.readTree(record.value());
            return node.path("eventType").asText("UNKNOWN");
        } catch (Exception e) {
            return "UNKNOWN";
        }
    }
}
```

### Kafka — `AuditEventMapper`

```java
/**
 * Mapea eventos de Kafka a RegistrarAuditCommand.
 * Conoce la estructura de cada tipo de evento de dominio del sistema.
 */
public class AuditEventMapper {

    private static final Map<String, String> TOPIC_TO_ENTIDAD = Map.ofEntries(
        Map.entry("controlstock.catalog.producto-creado", "Producto"),
        Map.entry("controlstock.catalog.producto-actualizado", "Producto"),
        Map.entry("controlstock.catalog.producto-inactivado", "Producto"),
        Map.entry("controlstock.inventory.entradas", "Movimiento"),
        Map.entry("controlstock.inventory.salidas", "Movimiento"),
        Map.entry("controlstock.inventory.stock-actualizado", "StockItem"),
        Map.entry("controlstock.adjustment.ajuste-solicitado", "AdjustmentRequest"),
        Map.entry("controlstock.adjustment.ajuste-aprobado", "AdjustmentRequest"),
        Map.entry("controlstock.adjustment.ajuste-rechazado", "AdjustmentRequest"),
        Map.entry("controlstock.supplier.proveedor-creado", "Supplier"),
        Map.entry("controlstock.supplier.proveedor-actualizado", "Supplier"),
        Map.entry("controlstock.integration.solicitud-reposicion-enviada", "ReposicionRequest")
    );

    public static RegistrarAuditCommand toCommand(
            String topic,
            String eventType,
            String payload,
            ObjectMapper objectMapper) throws Exception {

        JsonNode node = objectMapper.readTree(payload);
        String entidadNombre = TOPIC_TO_ENTIDAD.getOrDefault(topic, "Unknown");
        UUID entidadId = extractAggregateId(node, topic);
        UUID usuarioId = extractUsuarioId(node);
        Instant timestamp = extractTimestamp(node);
        OperacionAudit operacion = OperacionAudit.fromEventType(eventType);

        return new RegistrarAuditCommand(
            new Entidad(entidadNombre),
            new EntidadId(entidadId),
            operacion,
            new UsuarioId(usuarioId),
            timestamp,
            extractValorAnterior(node, topic),
            extractValorPosterior(node, topic),
            buildContexto(node, topic),
            eventType
        );
    }

    private static UUID extractAggregateId(JsonNode node, String topic) {
        // Cada tipo de evento tiene su campo de ID de agregado
        // Orden de búsqueda: aggregateId, productoId, ajusteId, proveedorId, etc.
        for (String field : List.of("aggregateId", "productoId", "ajusteId",
                                    "proveedorId", "movimientoId", "stockItemId",
                                    "reposicionId", "id")) {
            JsonNode candidate = node.get(field);
            if (candidate != null && !candidate.isNull()) {
                return UUID.fromString(candidate.asText());
            }
        }
        throw new IllegalArgumentException(
            "No se pudo extraer aggregateId del evento en topic: " + topic);
    }

    private static UUID extractUsuarioId(JsonNode node) {
        for (String field : List.of("usuarioId", "usuarioSolicitante", "usuarioDecisor",
                                    "operadorId", "userId")) {
            JsonNode candidate = node.get(field);
            if (candidate != null && !candidate.isNull()) {
                try {
                    return UUID.fromString(candidate.asText());
                } catch (Exception ignored) {}
            }
        }
        // Si no hay usuario en el evento (ej: eventos del sistema), usar UUID de sistema
        return UUID.fromString("00000000-0000-0000-0000-000000000001");
    }

    private static Instant extractTimestamp(JsonNode node) {
        JsonNode ts = node.get("occurredAt");
        if (ts != null && !ts.isNull()) {
            return Instant.parse(ts.asText());
        }
        return Instant.now();
    }

    private static Map<String, Object> extractValorAnterior(JsonNode node, String topic) {
        JsonNode va = node.get("valorAnterior");
        if (va != null && !va.isNull()) {
            return convertJsonNodeToMap(va);
        }
        return null;
    }

    private static Map<String, Object> extractValorPosterior(JsonNode node, String topic) {
        JsonNode vp = node.get("valorPosterior");
        if (vp != null && !vp.isNull()) {
            return convertJsonNodeToMap(vp);
        }
        // Si no hay campo explícito, usar el payload completo como valor posterior
        return convertJsonNodeToMap(node);
    }

    private static Map<String, Object> buildContexto(JsonNode node, String topic) {
        Map<String, Object> ctx = new HashMap<>();
        ctx.put("topic", topic);
        ctx.put("kafkaKey", node.path("aggregateId").asText(""));
        return ctx;
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object> convertJsonNodeToMap(JsonNode node) {
        return new ObjectMapper().convertValue(node, Map.class);
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

# Configuración del consumer Kafka
spring:
  kafka:
    consumer:
      group-id: controlstock-audit-consumer
      auto-offset-reset: earliest
      key-deserializer: org.apache.kafka.common.serialization.StringDeserializer
      value-deserializer: org.apache.kafka.common.serialization.StringDeserializer
    # Subscripción por patrón — cubre todos los topics del sistema
    listener:
      topic-pattern: "controlstock\\.(catalog|inventory|adjustment|supplier|integration)\\..*"
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
                // Consulta de auditoría: solo Auditor y Admin
                .pathMatchers(HttpMethod.GET, "/audit")
                    .hasAnyRole("AUDITOR", "ADMIN")
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
| `GET` | `/audit` | Consultar log de auditoría. Filtros: `entidad`, `entidad_id`, `usuario_id`, `desde`, `hasta`, `operacion`. Paginado con `page` y `size`. | AUDITOR, ADMIN | 200 |

### Contrato de Request/Response

```json
// GET /audit?entidad=Producto&desde=2025-01-01T00:00:00Z&hasta=2025-01-31T23:59:59Z&page=0&size=20
// Response 200
{
  "content": [
    {
      "id": "uuid",
      "entidad": "Producto",
      "entidadId": "uuid-del-producto",
      "operacion": "CREAR",
      "usuarioId": "uuid-del-usuario",
      "timestampUtc": "2025-01-15T10:00:00Z",
      "valorAnterior": null,
      "valorPosterior": {
        "productoId": "uuid",
        "codigo": "PROD-001",
        "nombre": "Aceite Girasol 1L",
        "estado": "ACTIVO"
      },
      "contexto": {
        "topic": "controlstock.catalog.producto-creado",
        "kafkaKey": "uuid-del-producto"
      },
      "eventoOrigen": "ProductoCreado"
    }
  ],
  "page": 0,
  "size": 20,
  "totalElements": 1,
  "totalPages": 1
}

// GET /audit sin token → 401 Unauthorized
// GET /audit con rol OPERADOR → 403 Forbidden
// GET /audit?entidad_id=uuid-sin-registros → 200 con content: []
```

### Parámetros de Query

| Parámetro | Tipo | Obligatorio | Descripción |
|-----------|------|-------------|-------------|
| `entidad` | String | No | Filtrar por nombre de entidad (ej: `Producto`, `Supplier`) |
| `entidad_id` | UUID | No | Filtrar por ID de entidad afectada |
| `usuario_id` | UUID | No | Filtrar por usuario que originó el evento |
| `desde` | ISO-8601 | No | Timestamp inicio del rango temporal |
| `hasta` | ISO-8601 | No | Timestamp fin del rango temporal |
| `operacion` | Enum | No | `CREAR`, `MODIFICAR`, `INACTIVAR`, `MOVER`, `ANULAR`, `COMPENSAR` |
| `page` | Integer | No (default 0) | Número de página |
| `size` | Integer | No (default 20, max 100) | Tamaño de página |

### `@ExceptionHandler` en `GlobalExceptionHandler`

| Excepción | HTTP Status | Campo en body |
|-----------|-------------|---------------|
| `MethodArgumentTypeMismatchException` | 400 | parámetro de query inválido (UUID, fecha malformada) |
| `WebExchangeBindException` | 400 | errores de validación de parámetros |

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
| D-01 | `AuditRecordTest` | `crear_conDatosValidos_construyeRegistroInmutable` | Todos los campos preservados; `id` generado |
| D-02 | `AuditRecordTest` | `crear_conEntidadNula_lanzaExcepcion` | `NullPointerException` via `requireNonNull` |
| D-03 | `AuditRecordTest` | `crear_conEventoOrigenNulo_lanzaExcepcion` | `NullPointerException` |
| D-04 | `OperacionAuditTest` | `fromEventType_ProductoCreado_retornaCREAR` | `OperacionAudit.CREAR` |
| D-05 | `OperacionAuditTest` | `fromEventType_ProductoActualizado_retornaMODIFICAR` | `OperacionAudit.MODIFICAR` |
| D-06 | `OperacionAuditTest` | `fromEventType_ProductoInactivado_retornaINACTIVAR` | `OperacionAudit.INACTIVAR` |
| D-07 | `OperacionAuditTest` | `fromEventType_AjusteRevertido_retornaCOMPENSAR` | `OperacionAudit.COMPENSAR` |
| D-08 | `OperacionAuditTest` | `fromEventType_EntradaInventario_retornaMOVER` | `OperacionAudit.MOVER` |
| D-09 | `OperacionAuditTest` | `fromEventType_null_retornaMODIFICAR` | `OperacionAudit.MODIFICAR` (fallback) |
| D-10 | `EntidadTest` | `entidadVacia_lanzaExcepcion` | `EntidadVaciaException` |
| D-11 | `EntidadTest` | `entidadSuperaLimite100_lanzaExcepcion` | `EntidadDemasiadoLargaException` |

**Cobertura objetivo: dominio >= 90%**

### Capa de Aplicación

| # | Test Class | Caso de prueba | Mock / Aserción |
|---|-----------|----------------|-----------------|
| A-01 | `RegistrarAuditRecordUseCaseTest` | `ejecutar_eventoNuevo_guardaAuditRecord` | `auditLogRepository.save(AuditRecord)` llamado; `StepVerifier` verifica `Mono.empty()` retornado |
| A-02 | `RegistrarAuditRecordUseCaseTest` | `ejecutar_eventoDuplicado_descartaSilencioso` | `existsByEventoOrigenAndEntidadId` retorna `true`; `save(...)` NO llamado; sin error |
| A-03 | `RegistrarAuditRecordUseCaseTest` | `ejecutar_eventoOrigenNull_lanzaExcepcionDominio` | `expectError(NullPointerException.class)` |
| A-04 | `ConsultarAuditLogUseCaseTest` | `consultar_sinFiltros_retornaFluxDePaginaUno` | `auditLogRepository.findByFilter(emptyFilter, pageable)` llamado; `StepVerifier` verifica lista no vacía |
| A-05 | `ConsultarAuditLogUseCaseTest` | `consultar_conFiltroEntidad_delegaARepository` | `findByFilter` llamado con `filter.entidad() == "Producto"` |

**Cobertura objetivo: aplicación >= 85%**

### Capa de Infraestructura

| # | Test Class | Tipo | Caso de prueba |
|---|-----------|------|----------------|
| I-01 | `AuditLogR2dbcAdapterTest` | `@DataR2dbcTest` + Testcontainers PG | `save_insertaNuevoRegistro_recuperableConFindByFilter` |
| I-02 | `AuditLogR2dbcAdapterTest` | `@DataR2dbcTest` + Testcontainers PG | `save_dosVecesMismoEventoOrigen_ambosPersistidos` (el adapter NO verifica duplicados; lo hace el use case) |
| I-03 | `AuditLogR2dbcAdapterTest` | `@DataR2dbcTest` + Testcontainers PG | `existsByEventoOrigenAndEntidadId_retornaTrue_cuandoExiste` |
| I-04 | `AuditLogR2dbcAdapterTest` | `@DataR2dbcTest` + Testcontainers PG | `existsByEventoOrigenAndEntidadId_retornaFalse_cuandoNoExiste` |
| I-05 | `AuditLogR2dbcAdapterTest` | `@DataR2dbcTest` + Testcontainers PG | `findByFilter_conFiltroEntidad_retornaSoloRegistrosDeEntidad` |
| I-06 | `AuditLogR2dbcAdapterTest` | `@DataR2dbcTest` + Testcontainers PG | `findByFilter_conRangoDeFechas_retornaSoloRegistrosEnRango` |
| I-07 | `AuditKafkaConsumerIntegrationTest` | `@SpringBootTest` + Testcontainers PG + Kafka | `consumer_recibeProductoCreado_creaAuditRecordConOperacionCREAR` |
| I-08 | `AuditKafkaConsumerIntegrationTest` | `@SpringBootTest` + Testcontainers PG + Kafka | `consumer_recibeEventoDuplicado_noCreaDuplicadoEnAuditLog` |
| I-09 | `AuditKafkaConsumerIntegrationTest` | `@SpringBootTest` + Testcontainers PG + Kafka | `consumer_recibeAjusteAprobado_creaAuditRecordConOperacionMODIFICAR` |
| I-10 | `AuditKafkaConsumerIntegrationTest` | `@SpringBootTest` + Testcontainers PG + Kafka | `consumer_recibeProveedorActualizado_creaAuditRecordCorrectamente` |
| I-11 | `AuditEventMapperTest` | Unit test | `toCommand_PayloadProductoCreado_extrae_campos_correctos` |
| I-12 | `AuditEventMapperTest` | Unit test | `toCommand_PayloadSinUsuarioId_usaUsuarioSistema` |

**Cobertura objetivo: infraestructura >= 80%**

### API REST

| # | Test Class | Tipo | Caso de prueba |
|---|-----------|------|----------------|
| R-01 | `AuditControllerTest` | `@WebFluxTest` | `GET /audit con rol AUDITOR → 200 con lista de registros` |
| R-02 | `AuditControllerTest` | `@WebFluxTest` | `GET /audit con rol ADMIN → 200` |
| R-03 | `AuditControllerTest` | `@WebFluxTest` | `GET /audit con rol OPERADOR → 403` |
| R-04 | `AuditControllerTest` | `@WebFluxTest` | `GET /audit sin token → 401` |
| R-05 | `AuditControllerTest` | `@WebFluxTest` | `GET /audit?entidad=Producto → 200 con filtro aplicado` |
| R-06 | `AuditControllerTest` | `@WebFluxTest` | `GET /audit?entidad_id=uuid-valido → 200` |
| R-07 | `AuditControllerTest` | `@WebFluxTest` | `GET /audit?desde=2025-01-01T00:00:00Z&hasta=2025-01-31T23:59:59Z → 200` |
| R-08 | `AuditControllerTest` | `@WebFluxTest` | `GET /audit?operacion=CREAR → 200 solo con operación CREAR` |
| R-09 | `AuditControllerTest` | `@WebFluxTest` | `GET /audit?entidad_id=uuid-invalido → 400 (UUID malformado)` |
| R-10 | `AuditControllerTest` | `@WebFluxTest` | `GET /audit?desde=fecha-invalida → 400 (fecha malformada)` |

### Configuración Testcontainers

```java
// src/test/java/com/controlstock/audit/infrastructure/BaseIntegrationTest.java
@Testcontainers
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
public abstract class BaseIntegrationTest {

    @Container
    static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:16-alpine")
        .withDatabaseName("controlstock_audit_test")
        .withInitScript("db/schema-audit.sql");

    @Container
    static KafkaContainer kafka = new KafkaContainer(
        DockerImageName.parse("confluentinc/cp-kafka:7.6.0"));

    @DynamicPropertySource
    static void configureProperties(DynamicPropertyRegistry registry) {
        registry.add("spring.r2dbc.url",
            () -> "r2dbc:postgresql://" + postgres.getHost() + ":" +
                  postgres.getFirstMappedPort() + "/controlstock_audit_test");
        registry.add("spring.r2dbc.username", postgres::getUsername);
        registry.add("spring.r2dbc.password", postgres::getPassword);
        registry.add("spring.kafka.bootstrap-servers", kafka::getBootstrapServers);
        registry.add("spring.kafka.consumer.group-id",
            () -> "controlstock-audit-consumer-test");
    }
}
```

---

## Criterios de Aceptación

| # | Criterio | Verificación |
|---|---------|-------------|
| AC-01 | Al recibir `ProductoCreado` de Kafka, se crea un `AuditRecord` con `operacion: CREAR`, `entidad: Producto` y `eventoOrigen: ProductoCreado` | Test I-07; verificación manual via `GET /audit?entidad=Producto` en K3s |
| AC-02 | El mismo evento Kafka reenviado (reentrega Kafka) **no genera un registro duplicado** en `audit_log` (idempotencia verificada via `evento_origen + entidad_id`) | Test I-08, A-02 |
| AC-03 | La tabla `audit_log` **nunca admite UPDATE ni DELETE**: el adapter solo usa `INSERT` explícito via `DatabaseClient` | Revisión de código: ausencia de llamadas a `r2dbcRepo.save()` con entidades ya persistidas |
| AC-04 | `GET /audit` con rol `OPERADOR` devuelve **HTTP 403** | Test R-03 |
| AC-05 | `GET /audit` con filtros `entidad`, `entidad_id`, `usuario_id`, `desde`, `hasta`, `operacion` retorna solo los registros que coinciden | Tests R-05, R-06, R-07, R-08 |
| AC-06 | `GET /audit?entidad_id=uuid-malformado` devuelve **HTTP 400** con mensaje de error descriptivo | Test R-09 |
| AC-07 | El consumer Kafka escucha en el patrón `controlstock\.(catalog|inventory|adjustment|supplier|integration)\..*` — nuevos topics compatibles se capturan automáticamente | Verificación en K3s: topic nuevo en patrón genera audit record |
| AC-08 | Para eventos sin campo `usuarioId` en el payload, el sistema usa el UUID de sistema `00000000-0000-0000-0000-000000000001` como fallback | Test I-12; `AuditEventMapper` unit test |
| AC-09 | Cobertura: Dominio >= 90%, Aplicación >= 85%, Infraestructura >= 80% | JaCoCo en pipeline Jenkins |
| AC-10 | `GET /actuator/health/readiness` retorna `{ "status": "UP" }` con PostgreSQL y Kafka como health indicators | Verificación manual en K3s |
| AC-11 | Toda la cadena reactiva usa `StepVerifier`; ausencia de `block()` verificada con `BlockHound` | BlockHound activo en `@SpringBootTest` |
