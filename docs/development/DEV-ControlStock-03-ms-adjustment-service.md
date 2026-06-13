# Etapa 3d — Microservicio: Adjustment Service (BC-04)

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

El **Adjustment Service** (Bounded Context BC-04) es el microservicio responsable del ciclo de vida de las solicitudes de ajuste de inventario en ControlStock. Gestiona la creación, aprobación y rechazo de ajustes, delegando la aplicación del impacto al `inventory-service` (BC-03) mediante la publicación de eventos a Kafka. Es el **cuarto microservicio en implementarse**.

### Responsabilidades del servicio

| Responsabilidad | Descripción |
|----------------|-------------|
| **Gestión de solicitudes de ajuste** | Crear `AdjustmentRequest` en estado `PENDIENTE` con `motivo` obligatorio |
| **Decisión de ajuste** | Registrar aprobación o rechazo con usuario decisor y comentario opcional |
| **Publicación de decisiones via Outbox** | Publicar `AjusteAprobado` o `AjusteRechazado` via Outbox → Kafka para que `inventory-service` aplique el impacto |
| **Compensación Saga-02** | Exponer `POST /adjustments/{id}/compensar` (idempotente): revertir a estado `ERROR` y publicar `AjusteRevertido` |
| **Participación en Saga-02** | Pasos 1 y 2: creación del ajuste y registro de la decisión dentro de la saga distribuida |

### Lo que el servicio NO hace

| Restricción | Justificación |
|-------------|---------------|
| No aplica directamente el stock | El impacto de stock lo ejecuta `inventory-service` al consumir `AjusteAprobado` |
| No consume topics de Kafka | Solo produce eventos; no tiene consumidores Kafka |
| No tiene dependencias REST de otros servicios de dominio | Depende de Keycloak (validación de rol en JWT); nada más |
| No gestiona kardex ni movimientos | Esa responsabilidad pertenece a `inventory-service` |

### Bounded Context BC-04

```
┌────────────────────────────────────────────────────────────────────┐
│                    Adjustment Service (BC-04)                      │
│                                                                    │
│  ┌────────────────────────┐    ┌─────────────────────────────────┐ │
│  │  adjustment_requests   │    │     adjustment_decisions        │ │
│  │  PENDIENTE → APROBADO  │◄───│  usuario_decisor, comentario    │ │
│  │  PENDIENTE → RECHAZADO │    └─────────────────────────────────┘ │
│  │  * → ERROR (compensar) │                                        │
│  └─────────────┬──────────┘                                        │
│                │                                                    │
│                ▼                                                    │
│        ┌──────────────────────┐                                    │
│        │   outbox (PG)        │    ┌──────────────────────────┐    │
│        │   PENDING            │    │  processed_message       │    │
│        └──────────┬───────────┘    │  (idempotencia)          │    │
│                   │                └──────────────────────────┘    │
│          Outbox Relay (Scheduler R2DBC)                            │
└───────────────────────────────────────────────────────────────────┘
         │ (produce via outbox)
         ▼
┌─────────────────────────────────────────────┐
│  Apache Kafka                               │
│  controlstock.adjustment.ajuste-solicitado  │
│  controlstock.adjustment.ajuste-aprobado    │  ← consumido por inventory-service
│  controlstock.adjustment.ajuste-rechazado   │
│  controlstock.adjustment.ajuste-revertido   │  ← compensación Saga-02
└─────────────────────────────────────────────┘
```

### Base de datos

- **PostgreSQL 16** — schema `controlstock_adjustment` (adjustment_requests, adjustment_decisions, outbox, processed_message)
- **Tecnología de acceso**: Spring Data R2DBC (reactivo)

---

## Prerrequisitos

| Prerrequisito | Documento de referencia | Verificación |
|--------------|------------------------|-------------|
| Etapa 0 — Infraestructura base completa | `DEV-ControlStock-00-infrastructure.md` | K3s corriendo, namespaces activos |
| Etapa 0c — Observabilidad configurada | `DEV-ControlStock-0c-observability.md` | Prometheus + Grafana activos |
| Etapa 1 — Bases de datos aprovisionadas | `DEV-ControlStock-01-databases.md` | Schema `controlstock_adjustment` en PostgreSQL |
| Etapa 2 — Scaffold generado | `DEV-ControlStock-02-scaffold.md` | Proyecto Maven `adjustment-service` generado |
| Etapa 2b — Pipeline CI/CD configurado | `DEV-ControlStock-02b-cicd.md` | Job `adjustment-service` activo en Jenkins |
| **Etapa 3a — IAM Service corriendo** | `DEV-ControlStock-03-ms-iam-service.md` | Keycloak emitiendo tokens JWT con roles `SUPERVISOR`, `ADMIN`, `OPERADOR` para realm `controlstock` |
| Kafka (Strimzi KRaft) corriendo | Etapa 0 | Topics `controlstock.adjustment.*` creados |

### Verificación de prerrequisitos

```bash
# Verificar schema PostgreSQL adjustment
kubectl exec -n databases deploy/postgresql -- psql \
  -U controlstock_adjustment -d controlstock_adjustment \
  -c "\dt" | grep -E "adjustment_requests|adjustment_decisions|outbox|processed_message"

# Verificar topics Kafka adjustment
kubectl exec -n kafka deploy/kafka -- \
  kafka-topics.sh --list --bootstrap-server kafka:9092 \
  | grep "controlstock.adjustment"
# Salida esperada:
# controlstock.adjustment.ajuste-aprobado
# controlstock.adjustment.ajuste-rechazado
# controlstock.adjustment.ajuste-revertido
# controlstock.adjustment.ajuste-solicitado

# Verificar IAM / roles Supervisor en token
TOKEN=$(curl -s -X POST \
  "http://<VPS_IP>:8180/realms/controlstock/protocol/openid-connect/token" \
  -d "client_id=test-client&grant_type=password&username=supervisor@test.com&password=test" \
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
| **I-1** | Dominio | Entidad `AdjustmentRequest`; VOs `Motivo`, `CantidadAjuste`, `ProductoId`; invariantes (`motivo` no vacío, `cantidad` ≠ 0) | Tests dominio GREEN |
| **I-2** | Dominio | Entidad `AdjustmentDecision`; transiciones de estado (`PENDIENTE → APROBADO/RECHAZADO`); excepción `AjusteNoEnPendienteException` | Tests transiciones GREEN |
| **I-3** | Dominio | Eventos de dominio: `AjusteSolicitado`, `AjusteAprobado`, `AjusteRechazado`, `AjusteRevertido` | Tests eventos GREEN |
| **I-4** | Dominio | Puertos: `AdjustmentRequestRepository`, `AdjustmentDecisionRepository`, `OutboxRepository`, `ProcessedMessageRepository` | Interfaces definidas; compilación GREEN |
| **I-5** | Aplicación | `CrearAjusteUseCase`, `AprobarAjusteUseCase`, `RechazarAjusteUseCase` | Tests aplicación con mocks GREEN |
| **I-6** | Aplicación | `CompensarAjusteUseCase` (idempotente via `processed_message`) | Tests idempotencia GREEN |
| **I-7** | Infraestructura | R2DBC adapters para `adjustment_requests`, `adjustment_decisions`, `outbox`, `processed_message` | Tests Testcontainers (PostgreSQL) GREEN |
| **I-8** | Infraestructura | `OutboxRelay` (scheduler R2DBC → Kafka) | Tests Testcontainers (PostgreSQL + Kafka) GREEN |
| **I-9** | API REST | Endpoints completos + `@ExceptionHandler` (403, 404, 409, 400) + validación de roles | Tests `@WebFluxTest` GREEN |
| **I-10** | Integración | Tests E2E en K3s: flujo completo crear → aprobar → `AjusteAprobado` en Kafka | Suite de humo GREEN |

---

## Capa de Dominio

### Entidades

#### `AdjustmentRequest`

```java
// src/main/java/com/controlstock/adjustment/domain/model/AdjustmentRequest.java
public class AdjustmentRequest {
    private final AjusteId id;
    private final ProductoId productoId;
    private final CantidadAjuste cantidad;    // puede ser positiva (entrada) o negativa (salida)
    private final Motivo motivo;
    private EstadoAjuste estado;              // PENDIENTE, APROBADO, RECHAZADO, ERROR
    private final UUID usuarioSolicitante;
    private UUID sagaId;
    private final Instant createdAt;
    private Instant updatedAt;

    public static AdjustmentRequest crear(
            ProductoId productoId,
            CantidadAjuste cantidad,
            Motivo motivo,
            UUID usuarioSolicitante,
            UUID sagaId) {
        return new AdjustmentRequest(
            new AjusteId(UUID.randomUUID()),
            productoId, cantidad, motivo,
            EstadoAjuste.PENDIENTE,
            usuarioSolicitante, sagaId,
            Instant.now(), Instant.now()
        );
    }

    /**
     * Aprueba el ajuste.
     * Invariante: solo se puede aprobar un ajuste PENDIENTE.
     */
    public List<DomainEvent> aprobar(UUID usuarioDecisor, String comentario) {
        if (this.estado != EstadoAjuste.PENDIENTE) {
            throw new AjusteNoEnPendienteException(this.id, this.estado);
        }
        this.estado = EstadoAjuste.APROBADO;
        this.updatedAt = Instant.now();
        return List.of(new AjusteAprobadoEvent(
            this.id.value(), this.productoId.value(),
            this.cantidad.value(), usuarioDecisor, this.sagaId, Instant.now()
        ));
    }

    /**
     * Rechaza el ajuste.
     * Invariante: solo se puede rechazar un ajuste PENDIENTE.
     */
    public List<DomainEvent> rechazar(UUID usuarioDecisor, String comentario) {
        if (this.estado != EstadoAjuste.PENDIENTE) {
            throw new AjusteNoEnPendienteException(this.id, this.estado);
        }
        this.estado = EstadoAjuste.RECHAZADO;
        this.updatedAt = Instant.now();
        return List.of(new AjusteRechazadoEvent(
            this.id.value(), this.productoId.value(),
            usuarioDecisor, comentario, Instant.now()
        ));
    }

    /**
     * Compensación Saga-02: fuerza estado a ERROR y desencadena AjusteRevertido.
     * Idempotente si ya está en ERROR.
     */
    public List<DomainEvent> compensar() {
        if (this.estado == EstadoAjuste.ERROR) {
            return Collections.emptyList(); // ya compensado — idempotente
        }
        this.estado = EstadoAjuste.ERROR;
        this.updatedAt = Instant.now();
        return List.of(new AjusteRevertidoEvent(
            this.id.value(), this.productoId.value(),
            this.cantidad.value(), this.sagaId, Instant.now()
        ));
    }

    public boolean isPendiente() { return EstadoAjuste.PENDIENTE == this.estado; }
    // Getters...
}
```

#### `AdjustmentDecision`

```java
// src/main/java/com/controlstock/adjustment/domain/model/AdjustmentDecision.java
public class AdjustmentDecision {
    private final DecisionId id;
    private final AjusteId adjustmentRequestId;
    private final TipoDecision decision;       // APROBADO, RECHAZADO
    private final String comentario;           // nullable
    private final UUID usuarioDecisor;
    private final Instant createdAt;

    public static AdjustmentDecision crear(
            AjusteId requestId,
            TipoDecision decision,
            String comentario,
            UUID usuarioDecisor) {
        return new AdjustmentDecision(
            new DecisionId(UUID.randomUUID()),
            requestId, decision, comentario,
            usuarioDecisor, Instant.now()
        );
    }
    // Registro inmutable — no hay setters
}
```

### Value Objects

| Value Object | Validaciones | Clase |
|-------------|-------------|-------|
| `ProductoId` | UUID no nulo | `com.controlstock.adjustment.domain.vo.ProductoId` |
| `AjusteId` | UUID no nulo | `com.controlstock.adjustment.domain.vo.AjusteId` |
| `DecisionId` | UUID no nulo | `com.controlstock.adjustment.domain.vo.DecisionId` |
| `CantidadAjuste` | `!= 0` (puede ser negativa), no nula, BigDecimal escala 3 | `com.controlstock.adjustment.domain.vo.CantidadAjuste` |
| `Motivo` | No nulo, no vacío, no solo espacios, máx 500 chars | `com.controlstock.adjustment.domain.vo.Motivo` |

```java
// CantidadAjuste: puede ser positiva (más stock) o negativa (menos stock), pero NUNCA cero
public record CantidadAjuste(BigDecimal value) {
    public CantidadAjuste {
        Objects.requireNonNull(value, "cantidad de ajuste no puede ser nula");
        if (value.compareTo(BigDecimal.ZERO) == 0) {
            throw new CantidadAjusteCeroException();
        }
        value = value.setScale(3, RoundingMode.HALF_UP);
    }
}

// Motivo: descripción textual obligatoria del ajuste
public record Motivo(String value) {
    public Motivo {
        Objects.requireNonNull(value, "motivo no puede ser nulo");
        if (value.isBlank()) {
            throw new MotivoVacioException();
        }
        if (value.length() > 500) {
            throw new MotivoDemasiadoLargoException(value.length());
        }
    }
}
```

### Excepciones de Dominio

```java
// Lanzada al intentar aprobar/rechazar un ajuste que no está en PENDIENTE
public class AjusteNoEnPendienteException extends RuntimeException {
    private final UUID ajusteId;
    private final EstadoAjuste estadoActual;

    public AjusteNoEnPendienteException(AjusteId id, EstadoAjuste estado) {
        super(String.format("El ajuste %s no está en estado PENDIENTE (estado actual: %s)",
            id.value(), estado));
        this.ajusteId = id.value();
        this.estadoActual = estado;
    }
}

// Lanzada cuando la cantidad de ajuste es cero
public class CantidadAjusteCeroException extends RuntimeException {
    public CantidadAjusteCeroException() {
        super("La cantidad de ajuste no puede ser cero");
    }
}

// Lanzada cuando el motivo está vacío o solo tiene espacios
public class MotivoVacioException extends RuntimeException {
    public MotivoVacioException() {
        super("El motivo del ajuste es obligatorio y no puede estar vacío");
    }
}
```

### Eventos de Dominio

```java
// AjusteSolicitado — publicado al crear una solicitud de ajuste
public record AjusteSolicitadoEvent(
    UUID ajusteId,
    UUID productoId,
    BigDecimal cantidad,
    String motivo,
    UUID usuarioSolicitante,
    UUID sagaId,
    Instant occurredAt
) implements DomainEvent {
    @Override public String getEventType()     { return "AjusteSolicitado"; }
    @Override public String getAggregateType() { return "AdjustmentRequest"; }
    @Override public UUID getAggregateId()     { return ajusteId; }
    @Override public Instant getOccurredAt()   { return occurredAt; }
    @Override public String getTopic() {
        return "controlstock.adjustment.ajuste-solicitado";
    }
}

// AjusteAprobado — consumido por inventory-service para aplicar stock
public record AjusteAprobadoEvent(
    UUID ajusteId,
    UUID productoId,
    BigDecimal delta,             // mismo valor que cantidad (positivo o negativo)
    UUID usuarioDecisor,
    UUID sagaId,
    Instant occurredAt
) implements DomainEvent {
    @Override public String getEventType()     { return "AjusteAprobado"; }
    @Override public String getAggregateType() { return "AdjustmentRequest"; }
    @Override public UUID getAggregateId()     { return ajusteId; }
    @Override public Instant getOccurredAt()   { return occurredAt; }
    @Override public String getTopic() {
        return "controlstock.adjustment.ajuste-aprobado";
    }
}

// AjusteRechazado
public record AjusteRechazadoEvent(
    UUID ajusteId,
    UUID productoId,
    UUID usuarioDecisor,
    String comentario,
    Instant occurredAt
) implements DomainEvent {
    @Override public String getEventType()     { return "AjusteRechazado"; }
    @Override public String getAggregateType() { return "AdjustmentRequest"; }
    @Override public UUID getAggregateId()     { return ajusteId; }
    @Override public Instant getOccurredAt()   { return occurredAt; }
    @Override public String getTopic() {
        return "controlstock.adjustment.ajuste-rechazado";
    }
}

// AjusteRevertido — compensación Saga-02
public record AjusteRevertidoEvent(
    UUID ajusteId,
    UUID productoId,
    BigDecimal cantidadRevertida,
    UUID sagaId,
    Instant occurredAt
) implements DomainEvent {
    @Override public String getEventType()     { return "AjusteRevertido"; }
    @Override public String getAggregateType() { return "AdjustmentRequest"; }
    @Override public UUID getAggregateId()     { return ajusteId; }
    @Override public Instant getOccurredAt()   { return occurredAt; }
    @Override public String getTopic() {
        return "controlstock.adjustment.ajuste-revertido";
    }
}
```

### Topics de Kafka

| Evento | Topic | Partitions | Retention | Consumido por |
|--------|-------|-----------|-----------|---------------|
| `AjusteSolicitado` | `controlstock.adjustment.ajuste-solicitado` | 3 | 7 días | — |
| `AjusteAprobado` | `controlstock.adjustment.ajuste-aprobado` | 3 | 7 días | `inventory-service` |
| `AjusteRechazado` | `controlstock.adjustment.ajuste-rechazado` | 3 | 7 días | — |
| `AjusteRevertido` | `controlstock.adjustment.ajuste-revertido` | 3 | 7 días | — |

### Puertos (Interfaces de Dominio)

```java
// Puerto: AdjustmentRequestRepository (PostgreSQL, R2DBC)
public interface AdjustmentRequestRepository {
    Mono<AdjustmentRequest> save(AdjustmentRequest request);
    Mono<AdjustmentRequest> findById(AjusteId id);
    Flux<AdjustmentRequest> findAll(AjusteFilter filter, Pageable pageable);
}

// Puerto: AdjustmentDecisionRepository (PostgreSQL, R2DBC)
public interface AdjustmentDecisionRepository {
    Mono<AdjustmentDecision> save(AdjustmentDecision decision);
    Mono<AdjustmentDecision> findByAjusteId(AjusteId ajusteId);
}

// Puerto: OutboxRepository (PostgreSQL, R2DBC)
public interface OutboxRepository {
    Mono<Void> save(DomainEvent event);
    Flux<OutboxEntry> findPending(int limit);
    Mono<Void> markAsPublished(UUID outboxId);
    Mono<Void> markAsFailed(UUID outboxId);
}

// Puerto: ProcessedMessageRepository (idempotencia de compensación)
public interface ProcessedMessageRepository {
    Mono<Boolean> existsByMessageId(String messageId);
    Mono<Void> save(String messageId, String consumer);
}

// Puerto: EventPublisherPort (Kafka)
public interface EventPublisherPort {
    Mono<Void> publish(String topic, String key, String payload);
}
```

### Invariantes de Dominio

| Invariante | Regla | Excepción |
|-----------|-------|-----------|
| **Motivo obligatorio** | `motivo` no vacío ni solo espacios | `MotivoVacioException` |
| **Cantidad no cero** | `cantidad != 0` | `CantidadAjusteCeroException` |
| **Transición de estado válida** | Solo PENDIENTE puede aprobarse o rechazarse | `AjusteNoEnPendienteException` |
| **Rol requerido para decisión** | Solo SUPERVISOR o ADMIN puede aprobar/rechazar (verificado en use case y REST) | `AccesoNoAutorizadoException` |

---

## Capa de Aplicación

### Use Cases

#### `CrearAjusteUseCase`

```java
@Service
@RequiredArgsConstructor
public class CrearAjusteUseCase {
    private final AdjustmentRequestRepository requestRepository;
    private final OutboxRepository outboxRepository;
    private final TransactionalOperator transactionalOperator;

    /**
     * Crea una solicitud de ajuste en estado PENDIENTE.
     * Publica AjusteSolicitado via Outbox dentro de la misma transacción R2DBC.
     */
    public Mono<AjusteResponse> ejecutar(CrearAjusteCommand cmd) {
        return Mono.defer(() -> {
            AdjustmentRequest request = AdjustmentRequest.crear(
                cmd.productoId(), cmd.cantidad(), cmd.motivo(),
                cmd.usuarioSolicitante(), cmd.sagaId()
            );
            AjusteSolicitadoEvent evento = new AjusteSolicitadoEvent(
                request.getId().value(), cmd.productoId().value(),
                cmd.cantidad().value(), cmd.motivo().value(),
                cmd.usuarioSolicitante(), cmd.sagaId(), Instant.now()
            );
            return requestRepository.save(request)
                .then(outboxRepository.save(evento))
                .thenReturn(AjusteResponse.from(request));
        }).as(transactionalOperator::transactional);
    }
}
```

#### `AprobarAjusteUseCase`

```java
@Service
@RequiredArgsConstructor
public class AprobarAjusteUseCase {
    private final AdjustmentRequestRepository requestRepository;
    private final AdjustmentDecisionRepository decisionRepository;
    private final OutboxRepository outboxRepository;
    private final TransactionalOperator transactionalOperator;

    /**
     * Aprueba un ajuste PENDIENTE.
     * Requiere rol SUPERVISOR o ADMIN (verificado antes de llamar al use case).
     * Publica AjusteAprobado via Outbox — inventory-service lo consume para aplicar stock.
     */
    public Mono<AjusteResponse> ejecutar(DecidirAjusteCommand cmd) {
        return requestRepository.findById(cmd.ajusteId())
            .switchIfEmpty(Mono.error(new AjusteNoEncontradoException(cmd.ajusteId())))
            .flatMap(request -> {
                // Domain invariant: throws AjusteNoEnPendienteException if not PENDIENTE
                List<DomainEvent> eventos = request.aprobar(cmd.usuarioDecisor(), cmd.comentario());

                AdjustmentDecision decision = AdjustmentDecision.crear(
                    request.getId(), TipoDecision.APROBADO,
                    cmd.comentario(), cmd.usuarioDecisor()
                );

                return requestRepository.save(request)
                    .then(decisionRepository.save(decision))
                    .then(Flux.fromIterable(eventos)
                        .flatMap(outboxRepository::save)
                        .then())
                    .thenReturn(AjusteResponse.from(request));
            })
            .as(transactionalOperator::transactional);
    }
}
```

#### `RechazarAjusteUseCase`

```java
@Service
@RequiredArgsConstructor
public class RechazarAjusteUseCase {
    private final AdjustmentRequestRepository requestRepository;
    private final AdjustmentDecisionRepository decisionRepository;
    private final OutboxRepository outboxRepository;
    private final TransactionalOperator transactionalOperator;

    /**
     * Rechaza un ajuste PENDIENTE.
     * Requiere rol SUPERVISOR o ADMIN.
     * Publica AjusteRechazado via Outbox.
     */
    public Mono<AjusteResponse> ejecutar(DecidirAjusteCommand cmd) {
        return requestRepository.findById(cmd.ajusteId())
            .switchIfEmpty(Mono.error(new AjusteNoEncontradoException(cmd.ajusteId())))
            .flatMap(request -> {
                List<DomainEvent> eventos = request.rechazar(cmd.usuarioDecisor(), cmd.comentario());
                AdjustmentDecision decision = AdjustmentDecision.crear(
                    request.getId(), TipoDecision.RECHAZADO,
                    cmd.comentario(), cmd.usuarioDecisor()
                );
                return requestRepository.save(request)
                    .then(decisionRepository.save(decision))
                    .then(Flux.fromIterable(eventos)
                        .flatMap(outboxRepository::save)
                        .then())
                    .thenReturn(AjusteResponse.from(request));
            })
            .as(transactionalOperator::transactional);
    }
}
```

#### `CompensarAjusteUseCase`

```java
@Service
@RequiredArgsConstructor
public class CompensarAjusteUseCase {
    private final AdjustmentRequestRepository requestRepository;
    private final OutboxRepository outboxRepository;
    private final ProcessedMessageRepository processedMessageRepo;
    private final TransactionalOperator transactionalOperator;

    /**
     * Compensación Saga-02: revierte el ajuste a estado ERROR y publica AjusteRevertido.
     * Idempotente: key = sagaId + ":AJUSTE_REVERTIDO"
     * Si ya fue compensado (estado == ERROR y processed_message contiene la clave), retorna empty.
     */
    public Mono<Void> ejecutar(UUID ajusteId) {
        return requestRepository.findById(new AjusteId(ajusteId))
            .switchIfEmpty(Mono.error(new AjusteNoEncontradoException(new AjusteId(ajusteId))))
            .flatMap(request -> {
                String compensationKey = request.getSagaId() + ":AJUSTE_REVERTIDO";
                return processedMessageRepo.existsByMessageId(compensationKey)
                    .flatMap(yaCompensado -> {
                        if (Boolean.TRUE.equals(yaCompensado)) {
                            return Mono.empty(); // idempotent: already compensated
                        }
                        // request.compensar() returns empty list if already ERROR (domain idempotency)
                        List<DomainEvent> eventos = request.compensar();
                        return requestRepository.save(request)
                            .then(Flux.fromIterable(eventos)
                                .flatMap(outboxRepository::save)
                                .then())
                            .then(processedMessageRepo.save(compensationKey,
                                  "CompensarAjusteUseCase"));
                    });
            })
            .as(transactionalOperator::transactional);
    }
}
```

### DTOs

```java
// Command: CrearAjusteCommand
public record CrearAjusteCommand(
    ProductoId productoId,
    CantidadAjuste cantidad,
    Motivo motivo,
    UUID usuarioSolicitante,
    UUID sagaId           // nullable
) {}

// Command: DecidirAjusteCommand (aprobar o rechazar)
public record DecidirAjusteCommand(
    AjusteId ajusteId,
    UUID usuarioDecisor,
    String comentario     // nullable en aprobación; recomendado en rechazo
) {}

// Response: AjusteResponse
public record AjusteResponse(
    UUID id,
    UUID productoId,
    BigDecimal cantidad,
    String motivo,
    String estado,
    UUID usuarioSolicitante,
    Instant createdAt,
    Instant updatedAt
) {
    public static AjusteResponse from(AdjustmentRequest request) { /* ... */ }
}
```

---

## Capa de Infraestructura

### R2DBC — `AdjustmentRequestR2dbcAdapter`

```java
@Repository
@RequiredArgsConstructor
public class AdjustmentRequestR2dbcAdapter implements AdjustmentRequestRepository {
    private final AdjustmentRequestR2dbcRepo r2dbcRepo;

    @Override
    public Mono<AdjustmentRequest> save(AdjustmentRequest request) {
        return r2dbcRepo.save(AdjustmentRequestMapper.toEntity(request))
            .map(AdjustmentRequestMapper::toDomain);
    }

    @Override
    public Mono<AdjustmentRequest> findById(AjusteId id) {
        return r2dbcRepo.findById(id.value())
            .map(AdjustmentRequestMapper::toDomain);
    }

    @Override
    public Flux<AdjustmentRequest> findAll(AjusteFilter filter, Pageable pageable) {
        // Construir query dinámica con criterios opcionales (estado, productoId)
        return r2dbcRepo.findByFilter(
            filter.estado() != null ? filter.estado().name() : null,
            filter.productoId() != null ? filter.productoId().value() : null,
            pageable
        ).map(AdjustmentRequestMapper::toDomain);
    }
}

// Spring Data R2DBC entity
@Table("adjustment_requests")
public class AdjustmentRequestEntity {
    @Id private UUID id;
    private UUID productoId;
    private BigDecimal cantidad;
    private String motivo;
    private String estado;
    private UUID usuarioSolicitante;
    private UUID sagaId;
    private Instant createdAt;
    private Instant updatedAt;
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

    @Scheduled(fixedDelay = 500)
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

### Kafka — Productor via Outbox

El `adjustment-service` **no tiene consumidores Kafka**. Solo produce via Outbox Relay.

```java
// Kafka producer adapter (EventPublisherPort implementation)
@Component
@RequiredArgsConstructor
public class KafkaEventPublisherAdapter implements EventPublisherPort {
    private final ReactiveKafkaProducerTemplate<String, String> kafkaTemplate;

    @Override
    public Mono<Void> publish(String topic, String key, String payload) {
        return kafkaTemplate.send(topic, key, payload)
            .doOnNext(result -> log.debug("Publicado en {}: offset={}",
                topic, result.recordMetadata().offset()))
            .then();
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
                .pathMatchers(HttpMethod.POST, "/adjustments/{id}/aprobar",
                                              "/adjustments/{id}/rechazar")
                    .hasAnyRole("SUPERVISOR", "ADMIN")
                .pathMatchers(HttpMethod.POST, "/adjustments/{id}/compensar")
                    .hasAnyRole("SYSTEM", "SAGA_COORDINATOR")
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
| `GET` | `/adjustments` | Listar solicitudes de ajuste (filtros: `estado`, `productoId`, paginado) | Autenticado | 200 |
| `POST` | `/adjustments` | Crear solicitud de ajuste (`motivo` obligatorio, `cantidad != 0`) | OPERADOR, SUPERVISOR, ADMIN | 201 |
| `GET` | `/adjustments/{id}` | Detalle de una solicitud | Autenticado | 200 |
| `POST` | `/adjustments/{id}/aprobar` | Aprobar ajuste PENDIENTE | SUPERVISOR, ADMIN | 200 |
| `POST` | `/adjustments/{id}/rechazar` | Rechazar ajuste PENDIENTE | SUPERVISOR, ADMIN | 200 |
| `POST` | `/adjustments/{id}/compensar` | Compensación Saga-02 (idempotente) | SYSTEM, SAGA_COORDINATOR | 200 |

### Contratos de Request/Response

```json
// POST /adjustments — crear solicitud
// Request
{
  "productoId": "uuid",
  "cantidad": -50.000,
  "motivo": "Merma detectada en conteo físico semanal",
  "sagaId": "uuid-opcional"
}
// Response 201
{
  "id": "uuid",
  "productoId": "uuid",
  "cantidad": -50.000,
  "motivo": "Merma detectada en conteo físico semanal",
  "estado": "PENDIENTE",
  "usuarioSolicitante": "uuid",
  "createdAt": "2025-01-15T10:00:00Z",
  "updatedAt": "2025-01-15T10:00:00Z"
}

// POST /adjustments/{id}/aprobar
// Request
{
  "comentario": "Merma verificada con conteo físico - acta adjunta"
}
// Response 200
{
  "id": "uuid",
  "estado": "APROBADO",
  "updatedAt": "2025-01-15T11:00:00Z"
}

// POST /adjustments/{id}/aprobar — ajuste no PENDIENTE
// Response 409 Conflict
{
  "error": "AJUSTE_NO_EN_PENDIENTE",
  "mensaje": "El ajuste no puede aprobarse porque no está en estado PENDIENTE",
  "ajusteId": "uuid",
  "estadoActual": "APROBADO"
}

// POST /adjustments — motivo vacío
// Response 400
{
  "error": "MOTIVO_VACIO",
  "mensaje": "El motivo del ajuste es obligatorio y no puede estar vacío"
}

// POST /adjustments/{id}/compensar — idempotente
// Response 200 OK (primer llamado y repeticiones)
{ "status": "COMPENSADO" }
```

### `@ExceptionHandler` en `GlobalExceptionHandler`

| Excepción | HTTP Status | Campo en body |
|-----------|-------------|---------------|
| `AjusteNoEncontradoException` | 404 | `ajusteId` |
| `AjusteNoEnPendienteException` | 409 | `ajusteId`, `estadoActual` |
| `MotivoVacioException` | 400 | `error: MOTIVO_VACIO` |
| `CantidadAjusteCeroException` | 400 | `error: CANTIDAD_CERO` |
| `AccesoNoAutorizadoException` | 403 | `error: ACCESO_NO_AUTORIZADO` |
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
| D-01 | `AdjustmentRequestTest` | `crear_conMotivoValido_estadoPendiente` | `estado == PENDIENTE` |
| D-02 | `AdjustmentRequestTest` | `crear_conMotivoVacio_lanzaExcepcion` | `assertThatThrownBy(...).isInstanceOf(MotivoVacioException.class)` |
| D-03 | `AdjustmentRequestTest` | `crear_conMotivoSoloEspacios_lanzaExcepcion` | `MotivoVacioException` |
| D-04 | `AdjustmentRequestTest` | `aprobar_ajustePendiente_cambiaEstado` | `estado == APROBADO`; retorna lista con `AjusteAprobadoEvent` |
| D-05 | `AdjustmentRequestTest` | `rechazar_ajustePendiente_cambiaEstado` | `estado == RECHAZADO`; retorna lista con `AjusteRechazadoEvent` |
| D-06 | `AdjustmentRequestTest` | `aprobar_ajusteYaAprobado_lanzaExcepcion` | `AjusteNoEnPendienteException` con `estadoActual == APROBADO` |
| D-07 | `AdjustmentRequestTest` | `rechazar_ajusteRechazado_lanzaExcepcion` | `AjusteNoEnPendienteException` |
| D-08 | `AdjustmentRequestTest` | `compensar_primeraVez_cambiaAError` | `estado == ERROR`; retorna `AjusteRevertidoEvent` |
| D-09 | `AdjustmentRequestTest` | `compensar_ajusteYaEnError_retornaListaVacia` | `estado == ERROR` (sin cambio); lista de eventos vacía — idempotencia a nivel dominio |
| D-10 | `CantidadAjusteTest` | `cantidad_cero_lanzaExcepcion` | `CantidadAjusteCeroException` |
| D-11 | `CantidadAjusteTest` | `cantidad_negativa_esValida` | No lanza excepción; `value == -50.000` |
| D-12 | `MotivoTest` | `motivo_superaLimite500_lanzaExcepcion` | `MotivoDemasiadoLargoException` |

**Cobertura objetivo: dominio ≥ 90%**

### Capa de Aplicación

| # | Test Class | Caso de prueba | Mock / Aserción |
|---|-----------|----------------|-----------------|
| A-01 | `CrearAjusteUseCaseTest` | `ejecutar_creaRequestYGuardaEvento` | `outboxRepo.save(AjusteSolicitadoEvent)` llamado; `StepVerifier` verifica response |
| A-02 | `CrearAjusteUseCaseTest` | `ejecutar_conMotivoVacioInRequest_lanzaExcepcion` | `expectError(MotivoVacioException.class)` (falla en constructor VO) |
| A-03 | `AprobarAjusteUseCaseTest` | `ejecutar_ajustePendiente_apruebayPublicaEvento` | `outboxRepo.save(AjusteAprobadoEvent)` llamado; `estado == APROBADO` |
| A-04 | `AprobarAjusteUseCaseTest` | `ejecutar_ajusteNoExiste_retorna404` | `expectError(AjusteNoEncontradoException.class)` |
| A-05 | `AprobarAjusteUseCaseTest` | `ejecutar_ajusteNoEnPendiente_retorna409` | `expectError(AjusteNoEnPendienteException.class)` |
| A-06 | `RechazarAjusteUseCaseTest` | `ejecutar_ajustePendiente_rechazaYPublicaEvento` | `outboxRepo.save(AjusteRechazadoEvent)` llamado; `estado == RECHAZADO` |
| A-07 | `CompensarAjusteUseCaseTest` | `ejecutar_primeraVez_cambia_aError_yPublicaRevertido` | `outboxRepo.save(AjusteRevertidoEvent)` llamado; `processedMessageRepo.save(...)` llamado |
| A-08 | `CompensarAjusteUseCaseTest` | `ejecutar_compensacionRepetida_noPublicaDuplicado` | `processedMessageRepo.existsByMessageId(...)` retorna `true`; repos de escritura NO son llamados |

**Cobertura objetivo: aplicación ≥ 85%**

### Capa de Infraestructura

| # | Test Class | Tipo | Caso de prueba |
|---|-----------|------|----------------|
| I-01 | `AdjustmentRequestR2dbcAdapterTest` | `@DataR2dbcTest` + Testcontainers PG | `save_findById_roundtrip_preservaMotivo` |
| I-02 | `AdjustmentRequestR2dbcAdapterTest` | `@DataR2dbcTest` + Testcontainers PG | `findAll_conFiltroEstado_retornaSoloPendientes` |
| I-03 | `AdjustmentDecisionR2dbcAdapterTest` | `@DataR2dbcTest` + Testcontainers PG | `save_decisionAprobada_findByAjusteId_roundtrip` |
| I-04 | `OutboxRelayIntegrationTest` | `@SpringBootTest` + Testcontainers PG + Kafka | `relay_publicaAjusteAprobado_en_topicCorrecto` — verificado con consumer Kafka |
| I-05 | `OutboxRelayIntegrationTest` | `@SpringBootTest` + Testcontainers PG + Kafka | `relay_falla_publicacion_marcaEntradaComoFailed` |

**Cobertura objetivo: infraestructura ≥ 80%**

### API REST

| # | Test Class | Tipo | Caso de prueba |
|---|-----------|------|----------------|
| R-01 | `AdjustmentControllerTest` | `@WebFluxTest` | `POST /adjustments → 201 con estado PENDIENTE` |
| R-02 | `AdjustmentControllerTest` | `@WebFluxTest` | `POST /adjustments motivo vacío → 400` |
| R-03 | `AdjustmentControllerTest` | `@WebFluxTest` | `POST /adjustments cantidad 0 → 400` |
| R-04 | `AdjustmentControllerTest` | `@WebFluxTest` | `POST /adjustments/{id}/aprobar con rol SUPERVISOR → 200` |
| R-05 | `AdjustmentControllerTest` | `@WebFluxTest` | `POST /adjustments/{id}/aprobar con rol OPERADOR → 403` |
| R-06 | `AdjustmentControllerTest` | `@WebFluxTest` | `POST /adjustments/{id}/aprobar ajuste no PENDIENTE → 409` |
| R-07 | `AdjustmentControllerTest` | `@WebFluxTest` | `POST /adjustments/{id}/rechazar con rol ADMIN → 200` |
| R-08 | `AdjustmentControllerTest` | `@WebFluxTest` | `POST /adjustments/{id}/compensar primera llamada → 200` |
| R-09 | `AdjustmentControllerTest` | `@WebFluxTest` | `POST /adjustments/{id}/compensar segunda llamada → 200 (idempotente)` |
| R-10 | `AdjustmentControllerTest` | `@WebFluxTest` | `GET /adjustments sin token → 401` |

### Configuración Testcontainers

```java
// src/test/java/com/controlstock/adjustment/infrastructure/BaseIntegrationTest.java
@Testcontainers
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
public abstract class BaseIntegrationTest {

    @Container
    static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:16-alpine")
        .withDatabaseName("controlstock_adjustment_test")
        .withInitScript("db/schema-adjustment.sql");

    @Container
    static KafkaContainer kafka = new KafkaContainer(
        DockerImageName.parse("confluentinc/cp-kafka:7.6.0"));

    @DynamicPropertySource
    static void configureProperties(DynamicPropertyRegistry registry) {
        registry.add("spring.r2dbc.url",
            () -> "r2dbc:postgresql://" + postgres.getHost() + ":" +
                  postgres.getFirstMappedPort() + "/controlstock_adjustment_test");
        registry.add("spring.r2dbc.username", postgres::getUsername);
        registry.add("spring.r2dbc.password", postgres::getPassword);
        registry.add("spring.kafka.bootstrap-servers", kafka::getBootstrapServers);
    }
}
```

---

## Criterios de Aceptación

| # | Criterio | Verificación |
|---|---------|-------------|
| AC-01 | `POST /adjustments` con `motivo` válido y `cantidad != 0` devuelve 201 con `estado: PENDIENTE` y evento `AjusteSolicitado` en Kafka | Test E2E + consumer Kafka |
| AC-02 | `POST /adjustments` con `motivo` vacío o `cantidad == 0` devuelve **HTTP 400** con mensaje de error descriptivo | Test R-02, R-03 |
| AC-03 | `POST /adjustments/{id}/aprobar` publica `AjusteAprobado` **exclusivamente via Outbox** — no hay dual-write directo a Kafka | Revisión de código: `EventPublisherPort` solo inyectado en `OutboxRelay` |
| AC-04 | `POST /adjustments/{id}/aprobar` con rol `OPERADOR` devuelve **HTTP 403** | Test R-05 |
| AC-05 | `POST /adjustments/{id}/aprobar` sobre ajuste no-`PENDIENTE` devuelve **HTTP 409** con `estadoActual` en body | Test R-06, A-05 |
| AC-06 | La compensación `POST /adjustments/{id}/compensar` es **idempotente**: la segunda llamada retorna HTTP 200 sin duplicar el evento `AjusteRevertido` en outbox | Test A-08, R-09 |
| AC-07 | `inventory-service` recibe el evento `AjusteAprobado` y aplica el delta de stock correctamente (test E2E inter-servicio) | Suite de integración cross-service en K3s |
| AC-08 | Cobertura: Dominio ≥ 90%, Aplicación ≥ 85%, Infraestructura ≥ 80% | JaCoCo en pipeline Jenkins |
| AC-09 | `GET /actuator/health/readiness` retorna `{ "status": "UP" }` con PostgreSQL y Kafka como health indicators | Verificación manual en K3s |
| AC-10 | Toda la cadena reactiva usa `StepVerifier`; ausencia de `block()` verificada con `BlockHound` | BlockHound activo en `@SpringBootTest` |
