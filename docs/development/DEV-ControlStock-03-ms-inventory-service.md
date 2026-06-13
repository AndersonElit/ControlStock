# Etapa 3c — Microservicio: Inventory Service (BC-03)

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

El **Inventory Service** (Bounded Context BC-03) es el microservicio responsable del control físico del stock en ControlStock. Es el **tercer microservicio en implementarse** y actúa como la fuente de verdad del inventario disponible: mantiene el nivel de stock actualizado atómicamente con cada movimiento, registra entradas y salidas, y construye el kardex como historial inmutable.

### Responsabilidades del servicio

| Responsabilidad | Descripción |
|----------------|-------------|
| **Mantenimiento de StockLevel** | Actualizar `stock_actual` atómicamente en cada movimiento con bloqueo optimista (`version`) |
| **Registro de movimientos** | Registrar ENTRADA y SALIDA; prevenir SALIDA sin stock suficiente (HTTP 409) |
| **Kardex append-only** | Crear `KardexRecord` inmutable tras cada movimiento como historial cronológico |
| **Aplicación de ajustes** | Consumir `AjusteAprobado` desde Kafka (Saga-02) de forma idempotente y actualizar stock |
| **Publicación de eventos de dominio** | Publicar `EntradaRegistrada`, `SalidaRegistrada`, `StockActualizado` via Outbox → Kafka |
| **Proyección de lectura** | Consumir propios eventos y mantener colecciones `stock`, `movimientos`, `kardex` en MongoDB |
| **Compensación Saga-01** | Exponer `POST /inventory/movements/{id}/compensar` (idempotente) para rollback de entrada |
| **Participación en sagas** | Paso 2 de Saga-01 (registrar entrada) y Paso 3 de Saga-02 (aplicar impacto de stock) |

### Lo que el servicio NO hace

| Restricción | Justificación |
|-------------|---------------|
| No valida existencia de productos | Confía en el productoId provisto; la integridad es responsabilidad del caller (Kong / Saga) |
| No tiene dependencias REST de otros servicios de dominio | Acoplamiento mínimo; recibe datos via Kafka o desde el request |
| No crea ni aprueba ajustes | La gestión de ajustes es responsabilidad de `adjustment-service` (BC-04) |
| No envía notificaciones | Las alertas de bajo stock son responsabilidad de `alert-service` (BC-05) |

### Bounded Context BC-03

```
┌──────────────────────────────────────────────────────────────────────────┐
│                      Inventory Service (BC-03)                           │
│                                                                          │
│  ┌──────────────┐    ┌──────────────────────┐    ┌───────────────────┐  │
│  │  stock_levels │    │ inventory_movements  │    │   outbox (PG)     │  │
│  │  (version OL) │◄───│ ENTRADA/SALIDA/AJUSTE│    │   PENDING         │  │
│  └──────┬───────┘    └──────────────────────┘    └─────────┬─────────┘  │
│         │                      │                            │            │
│         │            ┌─────────▼──────────┐      Outbox Relay           │
│         │            │ processed_message  │      (Scheduler R2DBC)      │
│         │            │ (idempotency table)│                │            │
│         └────────────┴────────────────────┘                │            │
└──────────────────────────────────────────────────────────────────────────┘
         │ (produce via outbox)                  │ (consume)
         ▼                                       ▼
┌─────────────────────────┐       ┌──────────────────────────────┐
│  Apache Kafka           │       │  controlstock.adjustment.    │
│  controlstock.inventory │       │  ajuste-aprobado             │
│  .entradas              │       │  (AjusteAprobado — Saga-02)  │
│  .salidas               │       └──────────────────────────────┘
│  .stock-actualizado     │
└────────────┬────────────┘
             │ (consume own events)
             ▼
┌─────────────────────────────────────────────────────┐
│  MongoDB Projection Consumer                        │
│  controlstock_readmodel                             │
│  → stock (por producto)                             │
│  → movimientos (proyección paginada)                │
│  → kardex (ventana deslizante por producto)         │
└─────────────────────────────────────────────────────┘
```

### Base de datos

- **PostgreSQL 16** — schema `controlstock_inventory` (escritura: stock_levels, inventory_movements, outbox, processed_message)
- **MongoDB 7** — base de datos `controlstock_readmodel`, colecciones `stock`, `movimientos`, `kardex` (lectura)
- **Tecnología de acceso**: Spring Data R2DBC (PostgreSQL reactivo) + ReactiveMongoTemplate

---

## Prerrequisitos

| Prerrequisito | Documento de referencia | Verificación |
|--------------|------------------------|-------------|
| Etapa 0 — Infraestructura base completa | `DEV-ControlStock-00-infrastructure.md` | K3s corriendo, namespaces `apps`, `databases`, `kafka` activos |
| Etapa 0c — Observabilidad configurada | `DEV-ControlStock-0c-observability.md` | Prometheus + Grafana activos |
| Etapa 1 — Bases de datos aprovisionadas | `DEV-ControlStock-01-databases.md` | Schema `controlstock_inventory` en PostgreSQL + colecciones en MongoDB |
| Etapa 2 — Scaffold generado | `DEV-ControlStock-02-scaffold.md` | Proyecto Maven `inventory-service` generado |
| Etapa 2b — Pipeline CI/CD configurado | `DEV-ControlStock-02b-cicd.md` | Job `inventory-service` activo en Jenkins |
| **Etapa 3a — IAM Service corriendo** | `DEV-ControlStock-03-ms-iam-service.md` | Keycloak emitiendo tokens JWT para realm `controlstock` |
| **Etapa 3b — Catalog Service corriendo** | `DEV-ControlStock-03-ms-catalog-service.md` | Productos creados en catálogo (productoId válidos referenciados en movimientos) |
| Kafka (Strimzi KRaft) corriendo | Etapa 0 | Topics `controlstock.inventory.*` y `controlstock.adjustment.*` creados |

### Verificación de prerrequisitos

```bash
# Verificar schema PostgreSQL inventory
kubectl exec -n databases deploy/postgresql -- psql \
  -U controlstock_inventory -d controlstock_inventory \
  -c "\dt" | grep -E "stock_levels|inventory_movements|outbox|processed_message"

# Verificar topics Kafka inventory
kubectl exec -n kafka deploy/kafka -- \
  kafka-topics.sh --list --bootstrap-server kafka:9092 \
  | grep "controlstock.inventory"
# Salida esperada:
# controlstock.inventory.entradas
# controlstock.inventory.salidas
# controlstock.inventory.stock-actualizado

# Verificar topic de ajustes aprobados (consumido por inventory)
kubectl exec -n kafka deploy/kafka -- \
  kafka-topics.sh --list --bootstrap-server kafka:9092 \
  | grep "controlstock.adjustment.ajuste-aprobado"

# Verificar MongoDB colecciones readmodel
kubectl exec -n databases deploy/mongodb -- mongosh \
  --eval "use controlstock_readmodel; db.getCollectionNames()" \
  | grep -E "stock|movimientos|kardex"

# Verificar catalog-service health (productos disponibles)
curl -s http://<VPS_IP>:30082/actuator/health/readiness | jq '.status'
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
│  2. Implementar mínimo código GREEN                  │
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
| **I-1** | Dominio | Entidades `StockLevel` (con version OL), `InventoryMovement`; VOs `ProductoId`, `Cantidad`, `ReferenciaDocumento` | Tests dominio GREEN; invariante SALIDA con stock insuficiente lanza excepción |
| **I-2** | Dominio | Entidad `KardexRecord` (append-only); eventos de dominio (`EntradaRegistrada`, `SalidaRegistrada`, `StockActualizado`) | Tests eventos GREEN |
| **I-3** | Dominio | Puertos: `StockLevelRepository`, `InventoryMovementRepository`, `OutboxRepository`, `ProcessedMessageRepository` | Interfaces definidas; compilación GREEN |
| **I-4** | Aplicación | `RegistrarEntradaUseCase`, `RegistrarSalidaUseCase` con lógica de negocio completa | Tests aplicación con mocks GREEN |
| **I-5** | Aplicación | `AnularMovimientoUseCase`, `AplicarAjusteUseCase` (idempotente), `CompensarMovimientoUseCase` | Tests idempotencia GREEN |
| **I-6** | Infraestructura | R2DBC adapters: `StockLevelR2dbcRepository` (con optimistic lock), `InventoryMovementR2dbcRepository`, `OutboxR2dbcRepository` | Tests Testcontainers (PostgreSQL) GREEN |
| **I-7** | Infraestructura | `OutboxRelay` (scheduler R2DBC → Kafka); `AjusteAprobadoConsumer` (idempotente via `processed_message`) | Tests Testcontainers (PostgreSQL + Kafka) GREEN |
| **I-8** | Infraestructura | MongoDB projection adapters (`StockMongoAdapter`, `MovimientoMongoAdapter`, `KardexMongoAdapter`) | Tests Testcontainers (MongoDB + Kafka) GREEN |
| **I-9** | API REST | Endpoints completos + `@ExceptionHandler` (409 StockInsuficiente, 404, 400) | Tests `@WebFluxTest` GREEN |
| **I-10** | Integración | Tests E2E en K3s: flujo completo ENTRADA/SALIDA → Kafka → MongoDB; compensación Saga | Suite de humo GREEN |

---

## Capa de Dominio

### Entidades

#### `StockLevel`

Representa el nivel actual de stock de un producto. Aplica **bloqueo optimista** via el campo `version` para prevenir actualizaciones concurrentes perdidas.

```java
// src/main/java/com/controlstock/inventory/domain/model/StockLevel.java
public class StockLevel {
    private final StockLevelId id;
    private final ProductoId productoId;
    private Cantidad stockActual;
    private Instant updatedAt;
    private long version;   // optimistic locking — mapeado por R2DBC con @Version

    public static StockLevel inicializar(ProductoId productoId) {
        return new StockLevel(
            new StockLevelId(UUID.randomUUID()),
            productoId,
            new Cantidad(BigDecimal.ZERO),
            Instant.now(),
            0L
        );
    }

    /**
     * Aplica una ENTRADA: incrementa stock.
     * @return saldo resultante tras la entrada
     */
    public BigDecimal aplicarEntrada(Cantidad cantidad) {
        Objects.requireNonNull(cantidad, "cantidad no puede ser nula");
        this.stockActual = new Cantidad(this.stockActual.value().add(cantidad.value()));
        this.updatedAt = Instant.now();
        return this.stockActual.value();
    }

    /**
     * Aplica una SALIDA: reduce stock.
     * Invariante: stock_actual >= cantidad_solicitada
     * @throws StockInsuficienteException si el stock es insuficiente
     * @return saldo resultante tras la salida
     */
    public BigDecimal aplicarSalida(Cantidad cantidad) {
        Objects.requireNonNull(cantidad, "cantidad no puede ser nula");
        if (this.stockActual.value().compareTo(cantidad.value()) < 0) {
            throw new StockInsuficienteException(
                this.productoId,
                cantidad.value(),
                this.stockActual.value()
            );
        }
        this.stockActual = new Cantidad(this.stockActual.value().subtract(cantidad.value()));
        this.updatedAt = Instant.now();
        return this.stockActual.value();
    }

    /**
     * Aplica un AJUSTE (puede ser positivo o negativo).
     * Un ajuste negativo que lleva el stock a < 0 es rechazado.
     */
    public BigDecimal aplicarAjuste(BigDecimal delta) {
        BigDecimal nuevo = this.stockActual.value().add(delta);
        if (nuevo.compareTo(BigDecimal.ZERO) < 0) {
            throw new StockInsuficienteException(
                this.productoId,
                delta.negate(),
                this.stockActual.value()
            );
        }
        this.stockActual = new Cantidad(nuevo);
        this.updatedAt = Instant.now();
        return this.stockActual.value();
    }

    // Getters
    public StockLevelId getId()        { return id; }
    public ProductoId getProductoId()  { return productoId; }
    public Cantidad getStockActual()   { return stockActual; }
    public Instant getUpdatedAt()      { return updatedAt; }
    public long getVersion()           { return version; }
}
```

#### `InventoryMovement`

```java
// src/main/java/com/controlstock/inventory/domain/model/InventoryMovement.java
public class InventoryMovement {
    private final MovimientoId id;
    private final ProductoId productoId;
    private final TipoMovimiento tipo;            // ENTRADA, SALIDA, AJUSTE
    private final Cantidad cantidad;
    private final ReferenciaDocumento referenciaDocumento;
    private final LocalDate fecha;
    private final BigDecimal saldoResultante;
    private EstadoMovimiento estado;              // ACTIVO, ANULADO
    private final UUID usuarioId;
    private final UUID sagaId;                    // null si no pertenece a saga
    private final Instant createdAt;

    public static InventoryMovement crear(
            ProductoId productoId,
            TipoMovimiento tipo,
            Cantidad cantidad,
            ReferenciaDocumento referencia,
            LocalDate fecha,
            BigDecimal saldoResultante,
            UUID usuarioId,
            UUID sagaId) {
        return new InventoryMovement(
            new MovimientoId(UUID.randomUUID()),
            productoId, tipo, cantidad, referencia, fecha,
            saldoResultante, EstadoMovimiento.ACTIVO,
            usuarioId, sagaId, Instant.now()
        );
    }

    /**
     * Anula el movimiento. Un movimiento anulado permanece en el kardex
     * como registro histórico con estado ANULADO.
     */
    public void anular() {
        if (this.estado == EstadoMovimiento.ANULADO) {
            throw new MovimientoYaAnuladoException(this.id);
        }
        this.estado = EstadoMovimiento.ANULADO;
    }

    public boolean isActivo() { return EstadoMovimiento.ACTIVO == this.estado; }
    // Getters...
}
```

#### `KardexRecord`

Registro **append-only** e **inmutable**. Jamás se actualiza; solo se inserta. La anulación de un movimiento agrega una nueva entrada en el kardex con tipo ANULACION.

```java
// src/main/java/com/controlstock/inventory/domain/model/KardexRecord.java
public final class KardexRecord {
    private final KardexId id;
    private final ProductoId productoId;
    private final MovimientoId movimientoId;
    private final TipoMovimiento tipo;
    private final Cantidad cantidad;
    private final BigDecimal saldoAntes;
    private final BigDecimal saldoDespues;
    private final String descripcion;
    private final Instant registradoAt;

    // Solo constructor: no hay setters — registro inmutable
    public static KardexRecord crear(
            ProductoId productoId,
            MovimientoId movimientoId,
            TipoMovimiento tipo,
            Cantidad cantidad,
            BigDecimal saldoAntes,
            BigDecimal saldoDespues,
            String descripcion) {
        return new KardexRecord(
            new KardexId(UUID.randomUUID()),
            productoId, movimientoId, tipo, cantidad,
            saldoAntes, saldoDespues, descripcion, Instant.now()
        );
    }
}
```

### Value Objects

| Value Object | Validaciones | Clase |
|-------------|-------------|-------|
| `ProductoId` | UUID no nulo | `com.controlstock.inventory.domain.vo.ProductoId` |
| `Cantidad` | `> 0`, no nulo, BigDecimal con escala 3 | `com.controlstock.inventory.domain.vo.Cantidad` |
| `ReferenciaDocumento` | No nula, no vacía, no solo espacios, máx 100 chars | `com.controlstock.inventory.domain.vo.ReferenciaDocumento` |
| `MovimientoId` | UUID no nulo | `com.controlstock.inventory.domain.vo.MovimientoId` |
| `StockLevelId` | UUID no nulo | `com.controlstock.inventory.domain.vo.StockLevelId` |
| `KardexId` | UUID no nulo | `com.controlstock.inventory.domain.vo.KardexId` |

```java
// Cantidad Value Object — DEBE ser > 0
public record Cantidad(BigDecimal value) {
    public Cantidad {
        Objects.requireNonNull(value, "cantidad no puede ser nula");
        if (value.compareTo(BigDecimal.ZERO) <= 0) {
            throw new CantidadNoPositivaException(value);
        }
        value = value.setScale(3, RoundingMode.HALF_UP);
    }
}

// ReferenciaDocumento Value Object
public record ReferenciaDocumento(String value) {
    public ReferenciaDocumento {
        Objects.requireNonNull(value, "referenciaDocumento no puede ser nula");
        if (value.isBlank()) {
            throw new ReferenciaDocumentoVaciaException();
        }
        if (value.length() > 100) {
            throw new ReferenciaDocumentoDemasiadoLargaException(value.length());
        }
    }
}
```

### Excepciones de Dominio

```java
// Lanzada cuando stock_actual < cantidad_solicitada en SALIDA o AJUSTE negativo
public class StockInsuficienteException extends RuntimeException {
    private final UUID productoId;
    private final BigDecimal cantidadSolicitada;
    private final BigDecimal stockDisponible;

    public StockInsuficienteException(ProductoId productoId,
                                      BigDecimal solicitada,
                                      BigDecimal disponible) {
        super(String.format(
            "Stock insuficiente para producto %s: solicitado=%s, disponible=%s",
            productoId.value(), solicitada, disponible));
        this.productoId = productoId.value();
        this.cantidadSolicitada = solicitada;
        this.stockDisponible = disponible;
    }
    // Getters para el ExceptionHandler (incluidos en body HTTP 409)
}
```

### Eventos de Dominio

```java
// Interfaz base (misma que en otros servicios)
public interface DomainEvent {
    String getEventType();
    String getAggregateType();
    UUID getAggregateId();
    Instant getOccurredAt();
    String getTopic();
}

// EntradaRegistrada — publicado vía Outbox tras registrar una ENTRADA
public record EntradaRegistrada(
    UUID movimientoId,
    UUID productoId,
    BigDecimal cantidad,
    BigDecimal saldoResultante,
    String referenciaDocumento,
    UUID sagaId,
    Instant occurredAt
) implements DomainEvent {
    @Override public String getEventType()     { return "EntradaRegistrada"; }
    @Override public String getAggregateType() { return "InventoryMovement"; }
    @Override public UUID getAggregateId()     { return movimientoId; }
    @Override public Instant getOccurredAt()   { return occurredAt; }
    @Override public String getTopic()         { return "controlstock.inventory.entradas"; }
}

// SalidaRegistrada — publicado vía Outbox tras registrar una SALIDA
public record SalidaRegistrada(
    UUID movimientoId,
    UUID productoId,
    BigDecimal cantidad,
    BigDecimal saldoResultante,
    String referenciaDocumento,
    UUID sagaId,
    Instant occurredAt
) implements DomainEvent {
    @Override public String getEventType()     { return "SalidaRegistrada"; }
    @Override public String getAggregateType() { return "InventoryMovement"; }
    @Override public UUID getAggregateId()     { return movimientoId; }
    @Override public Instant getOccurredAt()   { return occurredAt; }
    @Override public String getTopic()         { return "controlstock.inventory.salidas"; }
}

// StockActualizado — publicado vía Outbox cada vez que stock_actual cambia
public record StockActualizado(
    UUID productoId,
    BigDecimal stockActual,
    Instant occurredAt
) implements DomainEvent {
    @Override public String getEventType()     { return "StockActualizado"; }
    @Override public String getAggregateType() { return "StockLevel"; }
    @Override public UUID getAggregateId()     { return productoId; }
    @Override public Instant getOccurredAt()   { return occurredAt; }
    @Override public String getTopic()         { return "controlstock.inventory.stock-actualizado"; }
}

// EntradaRevertida — publicado vía Outbox durante compensación Saga-01
public record EntradaRevertida(
    UUID movimientoId,
    UUID productoId,
    BigDecimal cantidadRevertida,
    UUID sagaId,
    Instant occurredAt
) implements DomainEvent {
    @Override public String getEventType()     { return "EntradaRevertida"; }
    @Override public String getAggregateType() { return "InventoryMovement"; }
    @Override public UUID getAggregateId()     { return movimientoId; }
    @Override public Instant getOccurredAt()   { return occurredAt; }
    @Override public String getTopic()         { return "controlstock.inventory.entradas"; }
}
```

### Topics de Kafka

| Evento | Topic | Partitions | Retention |
|--------|-------|-----------|-----------|
| `EntradaRegistrada` | `controlstock.inventory.entradas` | 3 | 7 días |
| `SalidaRegistrada` | `controlstock.inventory.salidas` | 3 | 7 días |
| `StockActualizado` | `controlstock.inventory.stock-actualizado` | 3 | 7 días |
| `AjusteAprobado` (consumido) | `controlstock.adjustment.ajuste-aprobado` | 3 | 7 días |

### Puertos (Interfaces de Dominio)

```java
// Puerto: StockLevelRepository (PostgreSQL, R2DBC)
public interface StockLevelRepository {
    Mono<StockLevel> findByProductoId(ProductoId productoId);
    Mono<StockLevel> save(StockLevel stockLevel);  // throws OptimisticLockingFailureException
    Mono<StockLevel> findOrCreate(ProductoId productoId);
    Flux<StockLevel> findAll(StockFilter filter, Pageable pageable);
}

// Puerto: InventoryMovementRepository (PostgreSQL, R2DBC)
public interface InventoryMovementRepository {
    Mono<InventoryMovement> save(InventoryMovement movement);
    Mono<InventoryMovement> findById(MovimientoId id);
    Flux<InventoryMovement> findAll(MovimientoFilter filter, Pageable pageable);
    Mono<InventoryMovement> findBySagaIdAndTipo(UUID sagaId, TipoMovimiento tipo);
}

// Puerto: OutboxRepository (PostgreSQL, R2DBC)
public interface OutboxRepository {
    Mono<Void> save(DomainEvent event);
    Flux<OutboxEntry> findPending(int limit);
    Mono<Void> markAsPublished(UUID outboxId);
    Mono<Void> markAsFailed(UUID outboxId);
}

// Puerto: ProcessedMessageRepository (idempotencia de consumo Kafka)
public interface ProcessedMessageRepository {
    Mono<Boolean> existsByMessageId(String messageId);
    Mono<Void> save(String messageId, String consumer);
}

// Puerto: StockProjectionPort (MongoDB — colección `stock`)
public interface StockProjectionPort {
    Mono<Void> upsertStock(UUID productoId, BigDecimal stockActual, boolean bajominimo);
    Mono<StockDocument> findByProductoId(UUID productoId);
    Flux<StockDocument> findAll(StockFilter filter, Pageable pageable);
}

// Puerto: MovimientoProjectionPort (MongoDB — colección `movimientos`)
public interface MovimientoProjectionPort {
    Mono<Void> insert(MovimientoDocument documento);
    Flux<MovimientoDocument> findAll(MovimientoFilter filter, Pageable pageable);
    Mono<MovimientoDocument> findById(UUID movimientoId);
}

// Puerto: KardexProjectionPort (MongoDB — colección `kardex`)
public interface KardexProjectionPort {
    Mono<Void> appendEntry(UUID productoId, KardexEntryDocument entry);
    Mono<KardexDocument> findByProductoId(UUID productoId, Pageable pageable);
}

// Puerto: EventPublisherPort (Kafka)
public interface EventPublisherPort {
    Mono<Void> publish(String topic, String key, String payload);
}
```

### Invariantes de Dominio

| Invariante | Regla | Excepción |
|-----------|-------|-----------|
| **Stock no negativo** | `stock_actual >= 0` siempre (constraint DB + lógica dominio) | `StockInsuficienteException` |
| **Cantidad positiva** | `cantidad > 0` en todo movimiento | `CantidadNoPositivaException` |
| **Referencia obligatoria** | `referencia_documento` no vacía ni solo espacios | `ReferenciaDocumentoVaciaException` |
| **Anulación única** | Un movimiento ANULADO no puede anularse de nuevo | `MovimientoYaAnuladoException` |
| **Kardex inmutable** | `KardexRecord` nunca se modifica tras su creación | No aplica setter |

---

## Capa de Aplicación

### Use Cases

#### `RegistrarEntradaUseCase`

```java
// src/main/java/com/controlstock/inventory/application/usecase/RegistrarEntradaUseCase.java
@Service
@RequiredArgsConstructor
public class RegistrarEntradaUseCase {
    private final StockLevelRepository stockLevelRepository;
    private final InventoryMovementRepository movementRepository;
    private final OutboxRepository outboxRepository;
    private final TransactionalOperator transactionalOperator;

    /**
     * Registra una ENTRADA de inventario.
     * Todos los efectos (stock, movimiento, outbox x2) ocurren en la MISMA transacción R2DBC.
     * Los eventos se publican via outbox relay — nunca dual-write directo a Kafka.
     */
    public Mono<MovimientoResponse> ejecutar(RegistrarMovimientoCommand cmd) {
        return Mono.defer(() -> stockLevelRepository.findOrCreate(cmd.productoId())
            .flatMap(stock -> {
                BigDecimal saldoAntes = stock.getStockActual().value();
                BigDecimal saldoDespues = stock.aplicarEntrada(cmd.cantidad());

                InventoryMovement mov = InventoryMovement.crear(
                    cmd.productoId(), TipoMovimiento.ENTRADA, cmd.cantidad(),
                    cmd.referencia(), cmd.fecha(), saldoDespues,
                    cmd.usuarioId(), cmd.sagaId()
                );

                EntradaRegistrada evento = new EntradaRegistrada(
                    mov.getId().value(), cmd.productoId().value(),
                    cmd.cantidad().value(), saldoDespues,
                    cmd.referencia().value(), cmd.sagaId(), Instant.now()
                );
                StockActualizado stockEvt = new StockActualizado(
                    cmd.productoId().value(), saldoDespues, Instant.now()
                );

                return stockLevelRepository.save(stock)
                    .then(movementRepository.save(mov))
                    .then(outboxRepository.save(evento))
                    .then(outboxRepository.save(stockEvt))
                    .thenReturn(MovimientoResponse.from(mov));
            })
        ).as(transactionalOperator::transactional);
    }
}
```

#### `RegistrarSalidaUseCase`

```java
@Service
@RequiredArgsConstructor
public class RegistrarSalidaUseCase {
    private final StockLevelRepository stockLevelRepository;
    private final InventoryMovementRepository movementRepository;
    private final OutboxRepository outboxRepository;
    private final TransactionalOperator transactionalOperator;

    /**
     * Registra una SALIDA de inventario.
     * Si el stock es insuficiente, lanza StockInsuficienteException (HTTP 409 con stockDisponible).
     * Todo ocurre en la MISMA transacción R2DBC.
     */
    public Mono<MovimientoResponse> ejecutar(RegistrarMovimientoCommand cmd) {
        return Mono.defer(() -> stockLevelRepository.findByProductoId(cmd.productoId())
            .switchIfEmpty(Mono.error(new StockLevelNoEncontradoException(cmd.productoId())))
            .flatMap(stock -> {
                // Domain invariant: throws StockInsuficienteException if stock < cantidad
                BigDecimal saldoDespues = stock.aplicarSalida(cmd.cantidad());

                InventoryMovement mov = InventoryMovement.crear(
                    cmd.productoId(), TipoMovimiento.SALIDA, cmd.cantidad(),
                    cmd.referencia(), cmd.fecha(), saldoDespues,
                    cmd.usuarioId(), cmd.sagaId()
                );

                SalidaRegistrada evento = new SalidaRegistrada(
                    mov.getId().value(), cmd.productoId().value(),
                    cmd.cantidad().value(), saldoDespues,
                    cmd.referencia().value(), cmd.sagaId(), Instant.now()
                );
                StockActualizado stockEvt = new StockActualizado(
                    cmd.productoId().value(), saldoDespues, Instant.now()
                );

                return stockLevelRepository.save(stock)
                    .then(movementRepository.save(mov))
                    .then(outboxRepository.save(evento))
                    .then(outboxRepository.save(stockEvt))
                    .thenReturn(MovimientoResponse.from(mov));
            })
        ).as(transactionalOperator::transactional);
    }
}
```

#### `AnularMovimientoUseCase`

```java
@Service
@RequiredArgsConstructor
public class AnularMovimientoUseCase {
    private final InventoryMovementRepository movementRepository;
    private final TransactionalOperator transactionalOperator;

    /**
     * Anula un movimiento existente.
     * El movimiento permanece en el kardex con estado=ANULADO.
     * No revierte el stock (la anulación es administrativa; la compensación lo hace).
     */
    public Mono<Void> ejecutar(UUID movimientoId) {
        return movementRepository.findById(new MovimientoId(movimientoId))
            .switchIfEmpty(Mono.error(new MovimientoNoEncontradoException(movimientoId)))
            .flatMap(mov -> {
                mov.anular(); // throws MovimientoYaAnuladoException if already ANULADO
                return movementRepository.save(mov).then();
            })
            .as(transactionalOperator::transactional);
    }
}
```

#### `AplicarAjusteUseCase`

Consumidor **idempotente** de `AjusteAprobado`. Usa `processed_message` para garantizar at-most-once application.

```java
@Service
@RequiredArgsConstructor
public class AplicarAjusteUseCase {
    private final StockLevelRepository stockLevelRepository;
    private final InventoryMovementRepository movementRepository;
    private final OutboxRepository outboxRepository;
    private final ProcessedMessageRepository processedMessageRepo;
    private final TransactionalOperator transactionalOperator;

    /**
     * Aplica el impacto de un ajuste aprobado al stock.
     * Idempotente: si messageId ya está en processed_message, retorna Mono.empty().
     * messageId = sagaId + ":AJUSTE_APLICADO"
     */
    public Mono<Void> ejecutar(AjusteAprobadoEvent event) {
        String messageId = event.sagaId() + ":AJUSTE_APLICADO";
        return processedMessageRepo.existsByMessageId(messageId)
            .flatMap(yaProcessado -> {
                if (Boolean.TRUE.equals(yaProcessado)) {
                    return Mono.empty(); // idempotency: skip
                }
                return stockLevelRepository.findOrCreate(new ProductoId(event.productoId()))
                    .flatMap(stock -> {
                        BigDecimal saldoDespues = stock.aplicarAjuste(event.delta());
                        InventoryMovement mov = InventoryMovement.crear(
                            new ProductoId(event.productoId()), TipoMovimiento.AJUSTE,
                            new Cantidad(event.delta().abs()),
                            new ReferenciaDocumento("AJUSTE-" + event.ajusteId()),
                            LocalDate.now(), saldoDespues, event.usuarioId(), event.sagaId()
                        );
                        StockActualizado stockEvt = new StockActualizado(
                            event.productoId(), saldoDespues, Instant.now()
                        );
                        return stockLevelRepository.save(stock)
                            .then(movementRepository.save(mov))
                            .then(outboxRepository.save(stockEvt))
                            .then(processedMessageRepo.save(messageId, "AjusteAprobadoConsumer"));
                    });
            })
            .as(transactionalOperator::transactional);
    }
}
```

#### `CompensarMovimientoUseCase`

```java
@Service
@RequiredArgsConstructor
public class CompensarMovimientoUseCase {
    private final InventoryMovementRepository movementRepository;
    private final StockLevelRepository stockLevelRepository;
    private final OutboxRepository outboxRepository;
    private final ProcessedMessageRepository processedMessageRepo;
    private final TransactionalOperator transactionalOperator;

    /**
     * Compensación de Saga-01: revierte una entrada de stock.
     * Idempotente: key = sagaId + ":COMPENSADO"
     * Si ya fue compensado, retorna Mono.empty() (HTTP 200 al caller).
     */
    public Mono<Void> ejecutar(UUID movimientoId) {
        return movementRepository.findById(new MovimientoId(movimientoId))
            .switchIfEmpty(Mono.error(new MovimientoNoEncontradoException(movimientoId)))
            .flatMap(mov -> {
                UUID sagaId = mov.getSagaId();
                String compensationKey = sagaId + ":COMPENSADO";
                return processedMessageRepo.existsByMessageId(compensationKey)
                    .flatMap(yaCompensado -> {
                        if (Boolean.TRUE.equals(yaCompensado)) {
                            return Mono.empty(); // idempotent: already compensated
                        }
                        return stockLevelRepository.findByProductoId(mov.getProductoId())
                            .flatMap(stock -> {
                                // Revert: SALIDA de la cantidad que fue entrada
                                stock.aplicarSalida(mov.getCantidad());
                                mov.anular();
                                EntradaRevertida revertida = new EntradaRevertida(
                                    mov.getId().value(), mov.getProductoId().value(),
                                    mov.getCantidad().value(), sagaId, Instant.now()
                                );
                                return stockLevelRepository.save(stock)
                                    .then(movementRepository.save(mov))
                                    .then(outboxRepository.save(revertida))
                                    .then(processedMessageRepo.save(compensationKey,
                                          "CompensarMovimientoUseCase"));
                            });
                    });
            })
            .as(transactionalOperator::transactional);
    }
}
```

### DTOs

```java
// Command: RegistrarMovimientoCommand
public record RegistrarMovimientoCommand(
    ProductoId productoId,
    Cantidad cantidad,
    ReferenciaDocumento referencia,
    LocalDate fecha,
    UUID usuarioId,
    UUID sagaId           // nullable — null si no viene de una saga
) {}

// Response: MovimientoResponse
public record MovimientoResponse(
    UUID id,
    UUID productoId,
    String tipo,
    BigDecimal cantidad,
    BigDecimal saldoResultante,
    String referenciaDocumento,
    LocalDate fecha,
    String estado,
    UUID usuarioId,
    Instant createdAt
) {
    public static MovimientoResponse from(InventoryMovement mov) { /* ... */ }
}

// Response: StockResponse
public record StockResponse(
    UUID productoId,
    BigDecimal stockActual,
    boolean bajominimo,
    Instant updatedAt
) {}
```

---

## Capa de Infraestructura

### R2DBC — Adapter `StockLevelR2dbcAdapter`

```java
// src/main/java/com/controlstock/inventory/infrastructure/r2dbc/StockLevelR2dbcAdapter.java
@Repository
@RequiredArgsConstructor
public class StockLevelR2dbcAdapter implements StockLevelRepository {

    private final StockLevelR2dbcRepo r2dbcRepo;   // Spring Data R2DBC repository

    @Override
    public Mono<StockLevel> findByProductoId(ProductoId productoId) {
        return r2dbcRepo.findByProductoId(productoId.value())
            .map(StockLevelMapper::toDomain);
    }

    @Override
    public Mono<StockLevel> save(StockLevel stockLevel) {
        return r2dbcRepo.save(StockLevelMapper.toEntity(stockLevel))
            // Spring Data R2DBC lanza OptimisticLockingFailureException si version no coincide
            .onErrorMap(OptimisticLockingFailureException.class,
                e -> new StockConcurrencyException(stockLevel.getProductoId(), e))
            .map(StockLevelMapper::toDomain);
    }

    @Override
    public Mono<StockLevel> findOrCreate(ProductoId productoId) {
        return findByProductoId(productoId)
            .switchIfEmpty(save(StockLevel.inicializar(productoId)));
    }
}

// Spring Data R2DBC entity con @Version para optimistic locking
@Table("stock_levels")
public class StockLevelEntity {
    @Id private UUID id;
    private UUID productoId;
    private BigDecimal stockActual;
    private Instant updatedAt;
    @Version private long version;   // R2DBC maneja el incremento automático
}
```

### R2DBC — `OutboxRelay`

```java
@Component
@RequiredArgsConstructor
public class OutboxRelay {
    private final OutboxRepository outboxRepository;
    private final EventPublisherPort eventPublisher;
    private final TransactionalOperator tx;

    @Scheduled(fixedDelay = 500)   // cada 500ms
    public void relay() {
        outboxRepository.findPending(50)
            .flatMap(entry ->
                eventPublisher.publish(entry.getTopic(), entry.getAggregateId(), entry.getPayload())
                    .then(outboxRepository.markAsPublished(entry.getId()))
                    .onErrorResume(e -> {
                        log.error("OutboxRelay: fallo publicando {}", entry.getId(), e);
                        return outboxRepository.markAsFailed(entry.getId());
                    })
            )
            .as(tx::transactional)
            .subscribe();
    }
}
```

### Kafka — `AjusteAprobadoConsumer`

```java
@Component
@RequiredArgsConstructor
public class AjusteAprobadoConsumer {
    private final AplicarAjusteUseCase aplicarAjusteUseCase;

    @KafkaListener(
        topics = "controlstock.adjustment.ajuste-aprobado",
        groupId = "inventory-service-ajuste-consumer",
        containerFactory = "kafkaListenerContainerFactory"
    )
    public Mono<Void> consume(AjusteAprobadoEvent event) {
        // La idempotencia se garantiza en el use case via processed_message
        return aplicarAjusteUseCase.ejecutar(event)
            .doOnError(e -> log.error("Error aplicando ajuste aprobado: {}", event.ajusteId(), e));
        // En caso de error no transitorio, el mensaje queda en dead-letter topic
    }
}
```

### MongoDB — Projection Adapters

```java
// StockMongoAdapter — adapter del puerto StockProjectionPort
@Repository
@RequiredArgsConstructor
public class StockMongoAdapter implements StockProjectionPort {
    private final ReactiveMongoTemplate mongoTemplate;

    @Override
    public Mono<Void> upsertStock(UUID productoId, BigDecimal stockActual, boolean bajominimo) {
        Query query = Query.query(Criteria.where("productoId").is(productoId.toString()));
        Update update = new Update()
            .set("stockActual", stockActual)
            .set("bajominimo", bajominimo)
            .set("updatedAt", Instant.now())
            .setOnInsert("productoId", productoId.toString());
        return mongoTemplate.upsert(query, update, "stock").then();
    }
}

// KardexMongoAdapter — adapter del puerto KardexProjectionPort
@Repository
@RequiredArgsConstructor
public class KardexMongoAdapter implements KardexProjectionPort {
    private final ReactiveMongoTemplate mongoTemplate;

    /**
     * Append-only: agrega una entrada al array 'entradas' del documento kardex del producto.
     * Usa $push con $slice para mantener ventana deslizante de últimas 1000 entradas.
     */
    @Override
    public Mono<Void> appendEntry(UUID productoId, KardexEntryDocument entry) {
        Query query = Query.query(Criteria.where("productoId").is(productoId.toString()));
        Update update = new Update()
            .push("entradas")
                .slice(-1000)
                .each(entry)
            .setOnInsert("productoId", productoId.toString());
        return mongoTemplate.upsert(query, update, "kardex").then();
    }
}
```

### Estructura de Documentos MongoDB

```json
// Colección: stock
{
  "_id": "...",
  "productoId": "uuid",
  "stockActual": 150.000,
  "bajominimo": false,
  "updatedAt": "2025-01-15T10:30:00Z"
}

// Colección: movimientos
{
  "_id": "...",
  "movimientoId": "uuid",
  "productoId": "uuid",
  "tipo": "ENTRADA",
  "cantidad": 50.000,
  "saldoResultante": 150.000,
  "referenciaDocumento": "OC-2025-001",
  "fecha": "2025-01-15",
  "estado": "ACTIVO",
  "usuarioId": "uuid",
  "createdAt": "2025-01-15T10:30:00Z"
}

// Colección: kardex (ventana deslizante de últimas 1000 entradas por producto)
{
  "_id": "...",
  "productoId": "uuid",
  "entradas": [
    {
      "movimientoId": "uuid",
      "tipo": "ENTRADA",
      "cantidad": 50.000,
      "saldoAntes": 100.000,
      "saldoDespues": 150.000,
      "descripcion": "Entrada por OC-2025-001",
      "registradoAt": "2025-01-15T10:30:00Z"
    }
  ]
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
                .pathMatchers(HttpMethod.POST, "/inventory/movements/{id}/compensar")
                    .hasAnyRole("SYSTEM", "SAGA_COORDINATOR")
                .pathMatchers(HttpMethod.POST, "/inventory/movements/{id}/anular")
                    .hasAnyRole("SUPERVISOR", "ADMIN")
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
| `GET` | `/inventory/stock` | Listar stock actual (filtros: `categoriaId`, `bajominimo=true`) | Autenticado | 200 |
| `GET` | `/inventory/stock/{productId}` | Stock actual de un producto | Autenticado | 200 |
| `GET` | `/inventory/movements` | Listar movimientos paginados (filtros: `productoId`, `tipo`, `fechaDesde`, `fechaHasta`) | Autenticado | 200 |
| `POST` | `/inventory/movements` | Registrar movimiento (ENTRADA o SALIDA) | OPERADOR, ADMIN | 201 |
| `GET` | `/inventory/movements/{id}` | Detalle de un movimiento | Autenticado | 200 |
| `POST` | `/inventory/movements/{id}/anular` | Anular movimiento (permanece en Kardex) | SUPERVISOR, ADMIN | 200 |
| `GET` | `/inventory/kardex/{productId}` | Kardex cronológico con saldo acumulado | Autenticado | 200 |
| `POST` | `/inventory/movements/{id}/compensar` | Compensación Saga-01 (idempotente) | SYSTEM, SAGA_COORDINATOR | 200 |

### Contratos de Request/Response

```json
// POST /inventory/movements — ENTRADA
// Request
{
  "productoId": "uuid",
  "tipo": "ENTRADA",
  "cantidad": 50.000,
  "referenciaDocumento": "OC-2025-001",
  "fecha": "2025-01-15",
  "sagaId": "uuid-opcional"
}
// Response 201
{
  "id": "uuid",
  "productoId": "uuid",
  "tipo": "ENTRADA",
  "cantidad": 50.000,
  "saldoResultante": 150.000,
  "referenciaDocumento": "OC-2025-001",
  "fecha": "2025-01-15",
  "estado": "ACTIVO",
  "createdAt": "2025-01-15T10:30:00Z"
}

// POST /inventory/movements — SALIDA con stock insuficiente
// Response 409 Conflict
{
  "error": "STOCK_INSUFICIENTE",
  "mensaje": "Stock insuficiente para el producto solicitado",
  "productoId": "uuid",
  "cantidadSolicitada": 200.000,
  "stockDisponible": 150.000
}

// POST /inventory/movements/{id}/compensar — idempotente
// Response 200 OK (tanto primer llamado como repeticiones)
{ "status": "COMPENSADO" }
```

### `@ExceptionHandler` en `GlobalExceptionHandler`

| Excepción | HTTP Status | body |
|-----------|-------------|------|
| `StockInsuficienteException` | 409 | `{ error, productoId, cantidadSolicitada, stockDisponible }` |
| `StockConcurrencyException` | 409 | `{ error: "CONCURRENT_UPDATE" }` |
| `MovimientoNoEncontradoException` | 404 | `{ error, movimientoId }` |
| `StockLevelNoEncontradoException` | 404 | `{ error, productoId }` |
| `MovimientoYaAnuladoException` | 409 | `{ error, movimientoId }` |
| `CantidadNoPositivaException` | 400 | `{ error, valor }` |
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
| D-01 | `StockLevelTest` | `aplicarEntrada_incrementaStock` | `StepVerifier` no aplica (sync) — `assertThat(saldo).isEqualByComparingTo("150.000")` |
| D-02 | `StockLevelTest` | `aplicarSalida_conStockSuficiente` | `saldo == stockPrevio - cantidad` |
| D-03 | `StockLevelTest` | `aplicarSalida_conStockInsuficiente_lanzaExcepcion` | `assertThatThrownBy(...).isInstanceOf(StockInsuficienteException.class)` |
| D-04 | `StockLevelTest` | `aplicarSalida_conStockExacto_reduce_aCero` | `saldo == 0` (boundary: cantidad == stock_actual) |
| D-05 | `StockLevelTest` | `actualizacionesConcurrentes_version_incrementa` | `version` cambia después de `save` |
| D-06 | `InventoryMovementTest` | `crear_movimientoEntrada_estadoActivo` | `estado == ACTIVO`, `tipo == ENTRADA` |
| D-07 | `InventoryMovementTest` | `anular_movimientoActivo_cambia_estado` | `estado == ANULADO` |
| D-08 | `InventoryMovementTest` | `anular_movimientoYaAnulado_lanzaExcepcion` | `MovimientoYaAnuladoException` |
| D-09 | `KardexRecordTest` | `crear_kardexRecord_esTrueInmutable` | No tiene setters; intentar mutation falla en compilación |
| D-10 | `CantidadTest` | `cantidad_cero_lanzaExcepcion` | `CantidadNoPositivaException` |
| D-11 | `CantidadTest` | `cantidad_negativa_lanzaExcepcion` | `CantidadNoPositivaException` |
| D-12 | `ReferenciaDocumentoTest` | `referencia_soloEspacios_lanzaExcepcion` | `ReferenciaDocumentoVaciaException` |

**Cobertura objetivo: dominio ≥ 90%**

### Capa de Aplicación

| # | Test Class | Caso de prueba | Mock / Aserción |
|---|-----------|----------------|-----------------|
| A-01 | `RegistrarEntradaUseCaseTest` | `ejecutar_registraMovimientoYGuardaEnOutbox` | Mocks de repos; `StepVerifier.create(uc.ejecutar(cmd)).assertNext(r -> assertThat(r.tipo()).isEqualTo("ENTRADA")).verifyComplete()` |
| A-02 | `RegistrarEntradaUseCaseTest` | `ejecutar_guardaDosEventosEnOutbox` | Verifica `outboxRepo.save(...)` llamado 2 veces (`EntradaRegistrada` + `StockActualizado`) |
| A-03 | `RegistrarSalidaUseCaseTest` | `ejecutar_conStockSuficiente_registraSalida` | `saldoResultante == stockPrevio - cantidad` |
| A-04 | `RegistrarSalidaUseCaseTest` | `ejecutar_conStockInsuficiente_retorna409` | `StepVerifier.create(...).expectError(StockInsuficienteException.class).verify()` |
| A-05 | `AplicarAjusteUseCaseTest` | `ejecutar_primeraVez_aplicaAjusteYGuardaMessageId` | `processedMessageRepo.save(...)` llamado; `stockRepo.save(...)` llamado |
| A-06 | `AplicarAjusteUseCaseTest` | `ejecutar_mensajeDuplicado_noAplicaNada` | Cuando `processedMessageRepo.existsByMessageId(...)` retorna `true`, los otros repos NO son llamados |
| A-07 | `CompensarMovimientoUseCaseTest` | `ejecutar_primeraVez_anulaMovimientoYActualizaStock` | `outboxRepo.save(EntradaRevertida)` llamado; `stock.stockActual` reducido |
| A-08 | `CompensarMovimientoUseCaseTest` | `ejecutar_llamadaRepetida_retornaVacioSinEffectos` | Cuando ya en `processed_message`, repos de escritura NO son llamados — idempotencia verificada |
| A-09 | `AnularMovimientoUseCaseTest` | `ejecutar_movimientoExiste_cambia_estadoAAnulado` | `movementRepo.save(...)` con `estado == ANULADO` |
| A-10 | `AnularMovimientoUseCaseTest` | `ejecutar_movimientoNoExiste_retorna404` | `expectError(MovimientoNoEncontradoException.class)` |

**Cobertura objetivo: aplicación ≥ 85%**

### Capa de Infraestructura

| # | Test Class | Tipo | Caso de prueba |
|---|-----------|------|----------------|
| I-01 | `StockLevelR2dbcAdapterTest` | `@DataR2dbcTest` + Testcontainers PG | `findOrCreate_nuevoProducto_creaConStockCero` |
| I-02 | `StockLevelR2dbcAdapterTest` | `@DataR2dbcTest` + Testcontainers PG | `save_conVersionInvalida_lanzaStockConcurrencyException` — dos transacciones concurrentes modifican el mismo registro; la segunda falla |
| I-03 | `InventoryMovementR2dbcAdapterTest` | `@DataR2dbcTest` + Testcontainers PG | `save_findById_roundtrip` |
| I-04 | `OutboxRelayIntegrationTest` | `@SpringBootTest` + Testcontainers PG + Kafka | `outboxRelay_publicaEventoPendiente_yMarcaComoPublicado` — `StepVerifier` en consumer Kafka |
| I-05 | `AjusteAprobadoConsumerTest` | `@SpringBootTest` + Testcontainers PG + Kafka | `consume_mensajeNuevo_aplicaAjuste` |
| I-06 | `AjusteAprobadoConsumerTest` | `@SpringBootTest` + Testcontainers PG + Kafka | `consume_mensajeDuplicado_noAplicaDosVeces` — mismo messageId enviado 2 veces; stock incrementa 1 sola vez |
| I-07 | `StockMongoAdapterTest` | `@DataMongoTest` + Testcontainers Mongo | `upsertStock_inserta_yActualiza` |
| I-08 | `KardexMongoAdapterTest` | `@DataMongoTest` + Testcontainers Mongo | `appendEntry_mantiene_ventana_de_1000` — insertar 1001 entradas; array tiene max 1000 |

**Cobertura objetivo: infraestructura ≥ 80%**

### API REST

| # | Test Class | Tipo | Caso de prueba |
|---|-----------|------|----------------|
| R-01 | `InventoryControllerTest` | `@WebFluxTest` | `POST /inventory/movements ENTRADA → 201` |
| R-02 | `InventoryControllerTest` | `@WebFluxTest` | `POST /inventory/movements SALIDA con stock insuficiente → 409 con stockDisponible en body` |
| R-03 | `InventoryControllerTest` | `@WebFluxTest` | `POST /inventory/movements/{id}/compensar primera llamada → 200` |
| R-04 | `InventoryControllerTest` | `@WebFluxTest` | `POST /inventory/movements/{id}/compensar segunda llamada → 200 (idempotente, no error)` |
| R-05 | `InventoryControllerTest` | `@WebFluxTest` | `POST /inventory/movements sin token → 401` |
| R-06 | `InventoryControllerTest` | `@WebFluxTest` | `POST /inventory/movements/{id}/compensar con rol USER → 403` |
| R-07 | `InventoryControllerTest` | `@WebFluxTest` | `GET /inventory/kardex/{productId} → 200 con entradas ordenadas cronológicamente` |
| R-08 | `InventoryControllerTest` | `@WebFluxTest` | `GET /inventory/stock?bajominimo=true → 200 filtrando solo productos bajo mínimo` |

### Configuración Testcontainers

```java
// src/test/java/com/controlstock/inventory/infrastructure/BaseIntegrationTest.java
@Testcontainers
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
public abstract class BaseIntegrationTest {

    @Container
    static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:16-alpine")
        .withDatabaseName("controlstock_inventory_test")
        .withInitScript("db/schema-inventory.sql");

    @Container
    static MongoDBContainer mongo = new MongoDBContainer("mongo:7.0");

    @Container
    static KafkaContainer kafka = new KafkaContainer(
        DockerImageName.parse("confluentinc/cp-kafka:7.6.0"));

    @DynamicPropertySource
    static void configureProperties(DynamicPropertyRegistry registry) {
        registry.add("spring.r2dbc.url",
            () -> "r2dbc:postgresql://" + postgres.getHost() + ":" +
                  postgres.getFirstMappedPort() + "/controlstock_inventory_test");
        registry.add("spring.r2dbc.username", postgres::getUsername);
        registry.add("spring.r2dbc.password", postgres::getPassword);
        registry.add("spring.data.mongodb.uri", mongo::getReplicaSetUrl);
        registry.add("spring.kafka.bootstrap-servers", kafka::getBootstrapServers);
    }
}
```

---

## Criterios de Aceptación

| # | Criterio | Verificación |
|---|---------|-------------|
| AC-01 | `POST /inventory/movements` (ENTRADA) devuelve 201 con `saldoResultante` correcto y evento `EntradaRegistrada` en Kafka | Test E2E + consumer Kafka |
| AC-02 | `POST /inventory/movements` (SALIDA) con stock insuficiente devuelve **HTTP 409** con campos `cantidadSolicitada` y `stockDisponible` en el body | Test `@WebFluxTest` R-02 |
| AC-03 | Los eventos se publican **exclusivamente via Outbox** — no hay dual-write directo a Kafka desde use cases | Revisión de código: `EventPublisherPort` solo inyectado en `OutboxRelay` |
| AC-04 | La compensación `POST /inventory/movements/{id}/compensar` es **idempotente**: la segunda llamada retorna HTTP 200 sin crear duplicados en stock ni en outbox | Test A-08, R-04 |
| AC-05 | El consumer de `AjusteAprobado` usa `processed_message` para idempotencia: el mismo `sagaId+step` procesado dos veces solo aplica el ajuste una vez | Test I-06 |
| AC-06 | El bloqueo optimista en `stock_levels` previene actualizaciones perdidas en concurrencia: la segunda transacción concurrente recibe `StockConcurrencyException` | Test I-02 |
| AC-07 | El Kardex es **append-only**: nunca se modifica un `KardexRecord` existente; la anulación agrega una nueva entrada | Inspección de MongoDB: no hay operaciones `update` en la colección `kardex` |
| AC-08 | La colección `stock` en MongoDB se actualiza via projection consumer (lectura de Kafka), no directamente desde el use case | Revisión de arquitectura: `StockProjectionPort` solo inyectado en el projection consumer |
| AC-09 | Cobertura: Dominio ≥ 90%, Aplicación ≥ 85%, Infraestructura ≥ 80% | JaCoCo en pipeline Jenkins |
| AC-10 | `GET /actuator/health/readiness` retorna `{ "status": "UP" }` con PostgreSQL, MongoDB y Kafka como health indicators | Verificación manual en K3s |
| AC-11 | Toda la cadena reactiva usa `StepVerifier`; ausencia total de `block()` verificada con `BlockHound` en test suite | BlockHound activo en `@SpringBootTest` |
