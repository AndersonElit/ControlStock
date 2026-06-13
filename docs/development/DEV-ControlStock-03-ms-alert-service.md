# Etapa 3e — Microservicio: Alert Service (BC-05)

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

El **Alert Service** (Bounded Context BC-05) es el microservicio responsable de evaluar umbrales de stock y generar alertas operacionales en ControlStock. Es el **quinto microservicio en implementarse**. Consume eventos `StockActualizado` de Kafka, evalúa las reglas de alerta configuradas por producto y, cuando se detecta una condición de bajo stock o sobrestock, registra el evento de alerta y solicita notificación al `integration-service` de forma no bloqueante.

### Responsabilidades del servicio

| Responsabilidad | Descripción |
|----------------|-------------|
| **Evaluación de umbrales** | Comparar `stock_actual` contra `stock_mínimo` y `stock_máximo` configurados por producto |
| **Generación de alertas** | Crear `AlertEvent` (`BAJO_STOCK` o `SOBRESTOCK`) independientemente del resultado de notificación |
| **Solicitud de notificación** | Llamar a `integration-service` via REST interno K3s (WebClient, no-blocking, NON via Kong) |
| **Gestión de reconocimiento** | Permitir `RECONOCIDA` de una alerta activa via endpoint REST |
| **Resiliencia de notificación** | Si `integration-service` falla, el `AlertEvent` queda `ACTIVA` y el error se loguea; el mensaje Kafka se procesa correctamente |
| **Idempotencia de consumo** | Si `StockActualizado` es reentregado para mismo `productoId+timestamp`, no crear alerta duplicada |

### Lo que el servicio NO hace

| Restricción | Justificación |
|-------------|---------------|
| No participa en sagas | Flujo de alertas es unidireccional; no requiere compensación distribuida |
| No publica eventos de dominio vía Outbox | No hay otros servicios que consuman eventos de alerta |
| No accede a Kong para notificaciones | La llamada a `integration-service` es directa via DNS interno K3s (`*.apps.svc.cluster.local`) |
| No replica ni gestiona catálogo de productos | Lee `stock_mínimo`/`stock_máximo` desde su propia tabla `alert_rules`; Catalog gestiona la definición del producto |
| No envía notificaciones directamente | Las notificaciones (email, WhatsApp, push) son responsabilidad de `integration-service` |

### Bounded Context BC-05

```
┌────────────────────────────────────────────────────────────────────────┐
│                      Alert Service (BC-05)                             │
│                                                                        │
│  ┌──────────────────┐     ┌────────────────────────────────────────┐  │
│  │  alert_rules     │     │           alert_events                 │  │
│  │  producto_id     │──►  │  ACTIVA → RECONOCIDA → RESUELTA        │  │
│  │  stock_minimo    │     └────────────────────────────────────────┘  │
│  │  stock_maximo    │                                                  │
│  │  activo          │                                                  │
│  └──────────────────┘                                                  │
└────────────────────────────────────────────────────────────────────────┘
         ▲ (consume)                              │ (llamada REST interna)
         │                                        ▼
┌────────────────────────────┐    ┌────────────────────────────────────┐
│  Apache Kafka              │    │  integration-service               │
│  controlstock.inventory.   │    │  http://integration-service        │
│  stock-actualizado         │    │  .apps.svc.cluster.local:8089      │
│  (StockActualizado)        │    │  POST /internal/notifications      │
└────────────────────────────┘    │  (WebClient — non-blocking)        │
                                  └────────────────────────────────────┘
```

### Base de datos

- **PostgreSQL 16** — schema `controlstock_alert` (alert_rules, alert_events)
- **Tecnología de acceso**: Spring Data R2DBC (reactivo)

---

## Prerrequisitos

| Prerrequisito | Documento de referencia | Verificación |
|--------------|------------------------|-------------|
| Etapa 0 — Infraestructura base completa | `DEV-ControlStock-00-infrastructure.md` | K3s corriendo |
| Etapa 0c — Observabilidad configurada | `DEV-ControlStock-0c-observability.md` | Prometheus activo |
| Etapa 1 — Bases de datos aprovisionadas | `DEV-ControlStock-01-databases.md` | Schema `controlstock_alert` en PostgreSQL |
| Etapa 2 — Scaffold generado | `DEV-ControlStock-02-scaffold.md` | Proyecto Maven `alert-service` generado |
| Etapa 2b — Pipeline CI/CD configurado | `DEV-ControlStock-02b-cicd.md` | Job `alert-service` activo en Jenkins |
| **Etapa 3a — IAM Service corriendo** | `DEV-ControlStock-03-ms-iam-service.md` | Keycloak emitiendo tokens JWT para realm `controlstock` |
| **Etapa 3c — Inventory Service corriendo** | `DEV-ControlStock-03-ms-inventory-service.md` | Produciendo `StockActualizado` en `controlstock.inventory.stock-actualizado` |
| Kafka (Strimzi KRaft) corriendo | Etapa 0 | Topic `controlstock.inventory.stock-actualizado` creado |
| `integration-service` (mock en dev) | — | WireMock o NodePort 9999 disponible en K3s dev para simular `POST /internal/notifications` |

### Nota sobre `integration-service` en desarrollo

En el entorno de desarrollo K3s, `integration-service` puede ser simulado con WireMock desplegado como pod en el namespace `apps`. El test de infraestructura usa Testcontainers WireMock o WireMock en NodePort 9999. La URL real K3s es:

```
http://integration-service.apps.svc.cluster.local:8089/internal/notifications
```

### Verificación de prerrequisitos

```bash
# Verificar schema PostgreSQL alert
kubectl exec -n databases deploy/postgresql -- psql \
  -U controlstock_alert -d controlstock_alert \
  -c "\dt" | grep -E "alert_rules|alert_events"

# Verificar topic StockActualizado
kubectl exec -n kafka deploy/kafka -- \
  kafka-topics.sh --list --bootstrap-server kafka:9092 \
  | grep "controlstock.inventory.stock-actualizado"

# Verificar inventory-service produciendo eventos
kubectl exec -n kafka deploy/kafka -- \
  kafka-console-consumer.sh \
  --bootstrap-server kafka:9092 \
  --topic controlstock.inventory.stock-actualizado \
  --from-beginning --max-messages 3

# Verificar WireMock disponible (mock integration-service)
curl -s http://<VPS_IP>:9999/__admin/health | jq '.status'
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
| **I-1** | Dominio | Entidades `AlertRule` (umbrales por producto), `AlertEvent` (ACTIVA/RECONOCIDA/RESUELTA); VOs: `ProductoId`, `StockMinimo`, `StockMaximo`, `UmbralStock` | Tests dominio GREEN |
| **I-2** | Dominio | Lógica de evaluación de umbral (`evaluarStock`): determina `BAJO_STOCK` o `SOBRESTOCK` (boundary conditions) | Tests evaluación GREEN — especialmente `==` en umbrales |
| **I-3** | Dominio | Puertos: `AlertRuleRepository`, `AlertEventRepository`, `NotificationPort` | Interfaces definidas; compilación GREEN |
| **I-4** | Aplicación | `EvaluarStockUseCase` (con idempotencia de reentrega) | Tests aplicación con mocks GREEN |
| **I-5** | Aplicación | `ReconocerAlertaUseCase` | Tests aplicación GREEN |
| **I-6** | Infraestructura | R2DBC adapters para `alert_rules`, `alert_events` | Tests Testcontainers (PostgreSQL) GREEN |
| **I-7** | Infraestructura | `StockActualizadoConsumer` (Kafka listener reactivo) | Tests Testcontainers (PostgreSQL + Kafka) GREEN |
| **I-8** | Infraestructura | `IntegrationServiceNotificationAdapter` (WebClient) — con WireMock | Tests WebClient con WireMock Testcontainers GREEN |
| **I-9** | API REST | Endpoints `GET /alerts` y `POST /alerts/{id}/reconocer` | Tests `@WebFluxTest` GREEN |
| **I-10** | Integración | Tests E2E en K3s: `StockActualizado` → alerta generada → WireMock recibe notificación | Suite de humo GREEN |

---

## Capa de Dominio

### Entidades

#### `AlertRule`

Configuración de umbrales de alerta por producto. Determina cuándo se genera una alerta.

```java
// src/main/java/com/controlstock/alert/domain/model/AlertRule.java
public class AlertRule {
    private final AlertRuleId id;
    private final ProductoId productoId;
    private BigDecimal stockMinimo;    // alerta BAJO_STOCK cuando stock_actual <= stock_minimo
    private BigDecimal stockMaximo;    // alerta SOBRESTOCK cuando stock_actual >= stock_maximo
    private boolean activo;
    private final Instant createdAt;
    private Instant updatedAt;

    public static AlertRule crear(
            ProductoId productoId,
            BigDecimal stockMinimo,
            BigDecimal stockMaximo) {
        validarUmbrales(stockMinimo, stockMaximo);
        return new AlertRule(
            new AlertRuleId(UUID.randomUUID()),
            productoId, stockMinimo, stockMaximo,
            true, Instant.now(), Instant.now()
        );
    }

    /**
     * Evalúa si el stock actual activa una alerta.
     * Condición BAJO_STOCK: stock_actual <= stock_minimo (inclusivo en el umbral)
     * Condición SOBRESTOCK: stock_actual >= stock_maximo (inclusivo en el umbral)
     *
     * @return Optional<TipoAlerta> — empty si no hay condición de alerta
     */
    public Optional<TipoAlerta> evaluarStock(BigDecimal stockActual) {
        Objects.requireNonNull(stockActual, "stockActual no puede ser nulo");
        if (!this.activo) {
            return Optional.empty();
        }
        if (stockActual.compareTo(this.stockMinimo) <= 0) {
            return Optional.of(TipoAlerta.BAJO_STOCK);
        }
        if (stockActual.compareTo(this.stockMaximo) >= 0) {
            return Optional.of(TipoAlerta.SOBRESTOCK);
        }
        return Optional.empty();
    }

    private static void validarUmbrales(BigDecimal minimo, BigDecimal maximo) {
        Objects.requireNonNull(minimo, "stock_minimo no puede ser nulo");
        Objects.requireNonNull(maximo, "stock_maximo no puede ser nulo");
        if (minimo.compareTo(BigDecimal.ZERO) < 0) {
            throw new UmbralInvalidoException("stock_minimo no puede ser negativo");
        }
        if (maximo.compareTo(minimo) <= 0) {
            throw new UmbralInvalidoException("stock_maximo debe ser mayor que stock_minimo");
        }
    }

    public void desactivar() {
        this.activo = false;
        this.updatedAt = Instant.now();
    }

    // Getters...
}
```

#### `AlertEvent`

Registro de un evento de alerta generado. Transiciona `ACTIVA → RECONOCIDA → RESUELTA`.

```java
// src/main/java/com/controlstock/alert/domain/model/AlertEvent.java
public class AlertEvent {
    private final AlertEventId id;
    private final ProductoId productoId;
    private final TipoAlerta tipoAlerta;          // BAJO_STOCK, SOBRESTOCK
    private final BigDecimal stockActual;
    private final BigDecimal umbral;              // el umbral que fue excedido
    private EstadoAlerta estado;                  // ACTIVA, RECONOCIDA, RESUELTA
    private final Instant createdAt;
    private Instant updatedAt;

    public static AlertEvent crear(
            ProductoId productoId,
            TipoAlerta tipo,
            BigDecimal stockActual,
            BigDecimal umbral) {
        return new AlertEvent(
            new AlertEventId(UUID.randomUUID()),
            productoId, tipo, stockActual, umbral,
            EstadoAlerta.ACTIVA,
            Instant.now(), Instant.now()
        );
    }

    /**
     * Reconoce la alerta (operador la ve y la confirma).
     * Solo alertas ACTIVAS pueden reconocerse.
     */
    public void reconocer() {
        if (this.estado != EstadoAlerta.ACTIVA) {
            throw new AlertaNoActivaException(this.id, this.estado);
        }
        this.estado = EstadoAlerta.RECONOCIDA;
        this.updatedAt = Instant.now();
    }

    /**
     * Resuelve la alerta (stock volvió al rango normal).
     */
    public void resolver() {
        if (this.estado == EstadoAlerta.RESUELTA) {
            return; // ya resuelta — idempotente
        }
        this.estado = EstadoAlerta.RESUELTA;
        this.updatedAt = Instant.now();
    }

    public boolean isActiva() { return EstadoAlerta.ACTIVA == this.estado; }
    // Getters...
}
```

### Value Objects

| Value Object | Validaciones | Clase |
|-------------|-------------|-------|
| `ProductoId` | UUID no nulo | `com.controlstock.alert.domain.vo.ProductoId` |
| `AlertRuleId` | UUID no nulo | `com.controlstock.alert.domain.vo.AlertRuleId` |
| `AlertEventId` | UUID no nulo | `com.controlstock.alert.domain.vo.AlertEventId` |
| `TipoAlerta` | Enum: `BAJO_STOCK`, `SOBRESTOCK` | `com.controlstock.alert.domain.vo.TipoAlerta` |
| `EstadoAlerta` | Enum: `ACTIVA`, `RECONOCIDA`, `RESUELTA` | `com.controlstock.alert.domain.vo.EstadoAlerta` |

### Reglas de Evaluación de Umbral (Boundary Conditions)

```
BAJO_STOCK:  stock_actual <= stock_minimo   (el umbral ESTÁ incluido — boundary)
SOBRESTOCK:  stock_actual >= stock_maximo   (el umbral ESTÁ incluido — boundary)
NORMAL:      stock_minimo < stock_actual < stock_maximo

Ejemplos con stock_minimo=10, stock_maximo=100:
  stock_actual = 10  → BAJO_STOCK  (== stock_minimo, incluido)
  stock_actual = 9   → BAJO_STOCK  (< stock_minimo)
  stock_actual = 11  → NORMAL
  stock_actual = 99  → NORMAL
  stock_actual = 100 → SOBRESTOCK  (== stock_maximo, incluido)
  stock_actual = 101 → SOBRESTOCK  (> stock_maximo)
```

### Excepciones de Dominio

```java
// Lanzada al intentar reconocer una alerta que no está ACTIVA
public class AlertaNoActivaException extends RuntimeException {
    private final UUID alertaId;
    private final EstadoAlerta estadoActual;

    public AlertaNoActivaException(AlertEventId id, EstadoAlerta estado) {
        super(String.format("La alerta %s no puede reconocerse (estado actual: %s)",
            id.value(), estado));
        this.alertaId = id.value();
        this.estadoActual = estado;
    }
}

// Lanzada cuando los umbrales no son válidos
public class UmbralInvalidoException extends RuntimeException {
    public UmbralInvalidoException(String mensaje) {
        super(mensaje);
    }
}
```

### Puertos (Interfaces de Dominio)

```java
// Puerto: AlertRuleRepository (PostgreSQL, R2DBC)
public interface AlertRuleRepository {
    Mono<AlertRule> findByProductoId(ProductoId productoId);
    Mono<AlertRule> save(AlertRule rule);
    Flux<AlertRule> findAll(Pageable pageable);
}

// Puerto: AlertEventRepository (PostgreSQL, R2DBC)
public interface AlertEventRepository {
    Mono<AlertEvent> save(AlertEvent event);
    Mono<AlertEvent> findById(AlertEventId id);
    Flux<AlertEvent> findAll(AlertFilter filter, Pageable pageable);
    // Para idempotencia: buscar alerta activa del mismo producto+tipo reciente
    Mono<AlertEvent> findActivaByProductoIdAndTipo(ProductoId productoId, TipoAlerta tipo);
    // Para detectar reentrega: buscar alerta por productoId y timestamp del evento
    Mono<Boolean> existsByProductoIdAndCreatedAtAfter(ProductoId productoId, Instant since);
}

// Puerto: NotificationPort (HTTP REST a integration-service)
public interface NotificationPort {
    /**
     * Solicita envío de notificación a integration-service.
     * Llamada no-bloqueante (Mono<Void>).
     * En caso de error, el Mono termina con error; el caller decide si ignorar.
     */
    Mono<Void> enviarNotificacion(NotificationRequest request);
}
```

### Invariantes de Dominio

| Invariante | Regla | Excepción |
|-----------|-------|-----------|
| **Umbral mínimo no negativo** | `stock_minimo >= 0` | `UmbralInvalidoException` |
| **Umbral máximo mayor que mínimo** | `stock_maximo > stock_minimo` | `UmbralInvalidoException` |
| **Reconocimiento solo de ACTIVA** | Solo alertas `ACTIVA` pueden reconocerse | `AlertaNoActivaException` |
| **AlertEvent persiste siempre** | El `AlertEvent` se crea independientemente del resultado de la notificación | Garantía de implementación |

---

## Capa de Aplicación

### Use Cases

#### `EvaluarStockUseCase`

```java
// src/main/java/com/controlstock/alert/application/usecase/EvaluarStockUseCase.java
@Service
@RequiredArgsConstructor
public class EvaluarStockUseCase {
    private final AlertRuleRepository alertRuleRepository;
    private final AlertEventRepository alertEventRepository;
    private final NotificationPort notificationPort;

    /**
     * Evalúa el stock actualizado contra las reglas de alerta del producto.
     *
     * Flujo:
     * 1. Buscar AlertRule por productoId (si no existe, no hay alerta — skip)
     * 2. Idempotencia: si ya existe alerta activa del mismo tipo para el producto, skip
     * 3. evaluarStock() → Optional<TipoAlerta>
     * 4. Si hay alerta: crear AlertEvent y persistir
     * 5. Solicitar notificación a integration-service (WebClient)
     *    - Si falla: loguear error; NO relanzar — el mensaje Kafka se ACK igualmente
     * 6. Si no hay alerta: si había alerta ACTIVA anterior, resolver (stock volvió al rango)
     */
    public Mono<Void> ejecutar(StockActualizadoEvent event) {
        return alertRuleRepository.findByProductoId(new ProductoId(event.productoId()))
            .flatMap(rule -> {
                Optional<TipoAlerta> tipoAlerta = rule.evaluarStock(event.stockActual());

                if (tipoAlerta.isEmpty()) {
                    // Stock en rango normal: resolver alertas activas previas si las hay
                    return resolverAlertasActivas(event.productoId());
                }

                TipoAlerta tipo = tipoAlerta.get();

                // Idempotencia: no crear alerta duplicada si ya existe una ACTIVA del mismo tipo
                return alertEventRepository.findActivaByProductoIdAndTipo(
                        new ProductoId(event.productoId()), tipo)
                    .flatMap(alertaExistente -> Mono.empty()) // ya existe — skip
                    .switchIfEmpty(
                        crearYNotificar(event, rule, tipo)
                    );
            })
            .switchIfEmpty(Mono.empty()); // no hay AlertRule para este producto — skip
    }

    private Mono<Void> crearYNotificar(
            StockActualizadoEvent event, AlertRule rule, TipoAlerta tipo) {
        BigDecimal umbral = tipo == TipoAlerta.BAJO_STOCK
            ? rule.getStockMinimo()
            : rule.getStockMaximo();

        AlertEvent alerta = AlertEvent.crear(
            new ProductoId(event.productoId()), tipo,
            event.stockActual(), umbral
        );

        return alertEventRepository.save(alerta)
            .flatMap(saved -> {
                // Notificación: NO bloquear el flujo si falla
                NotificationRequest notif = new NotificationRequest(
                    saved.getId().value(), event.productoId(),
                    tipo.name(), event.stockActual(), umbral
                );
                return notificationPort.enviarNotificacion(notif)
                    .onErrorResume(e -> {
                        // Fallo de notificación NO falla el procesamiento del mensaje Kafka
                        log.error("Fallo notificando alerta {}: {}", saved.getId().value(), e.getMessage());
                        return Mono.empty();
                    });
            })
            .then();
    }

    private Mono<Void> resolverAlertasActivas(UUID productoId) {
        // Buscar y resolver alertas ACTIVAS del producto (stock volvió a rango normal)
        return alertEventRepository.findActivaByProductoIdAndTipo(
                new ProductoId(productoId), TipoAlerta.BAJO_STOCK)
            .doOnNext(AlertEvent::resolver)
            .flatMap(alertEventRepository::save)
            .then(alertEventRepository.findActivaByProductoIdAndTipo(
                    new ProductoId(productoId), TipoAlerta.SOBRESTOCK)
                .doOnNext(AlertEvent::resolver)
                .flatMap(alertEventRepository::save))
            .then();
    }
}
```

#### `ReconocerAlertaUseCase`

```java
@Service
@RequiredArgsConstructor
public class ReconocerAlertaUseCase {
    private final AlertEventRepository alertEventRepository;

    /**
     * Reconoce una alerta activa (el operador la vio y la confirma).
     * Invariante: solo alertas ACTIVAS pueden reconocerse.
     */
    public Mono<Void> ejecutar(UUID alertaId) {
        return alertEventRepository.findById(new AlertEventId(alertaId))
            .switchIfEmpty(Mono.error(new AlertaNoEncontradaException(alertaId)))
            .flatMap(alerta -> {
                alerta.reconocer(); // throws AlertaNoActivaException if not ACTIVA
                return alertEventRepository.save(alerta).then();
            });
    }
}
```

### DTOs

```java
// Event: StockActualizadoEvent (consumido desde Kafka)
public record StockActualizadoEvent(
    UUID productoId,
    BigDecimal stockActual,
    Instant occurredAt
) {}

// Request: NotificationRequest (enviado a integration-service)
public record NotificationRequest(
    UUID alertaId,
    UUID productoId,
    String tipo,
    BigDecimal stockActual,
    BigDecimal umbral
) {}

// Response: AlertaResponse
public record AlertaResponse(
    UUID id,
    UUID productoId,
    String tipoAlerta,
    BigDecimal stockActual,
    BigDecimal umbral,
    String estado,
    Instant createdAt,
    Instant updatedAt
) {
    public static AlertaResponse from(AlertEvent event) { /* ... */ }
}
```

---

## Capa de Infraestructura

### R2DBC — `AlertRuleR2dbcAdapter`

```java
@Repository
@RequiredArgsConstructor
public class AlertRuleR2dbcAdapter implements AlertRuleRepository {
    private final AlertRuleR2dbcRepo r2dbcRepo;

    @Override
    public Mono<AlertRule> findByProductoId(ProductoId productoId) {
        return r2dbcRepo.findByProductoId(productoId.value())
            .map(AlertRuleMapper::toDomain);
    }

    @Override
    public Mono<AlertRule> save(AlertRule rule) {
        return r2dbcRepo.save(AlertRuleMapper.toEntity(rule))
            .map(AlertRuleMapper::toDomain);
    }
}

// Spring Data R2DBC entity
@Table("alert_rules")
public class AlertRuleEntity {
    @Id private UUID id;
    private UUID productoId;
    private BigDecimal stockMinimo;
    private BigDecimal stockMaximo;
    private boolean activo;
    private Instant createdAt;
    private Instant updatedAt;
}
```

### R2DBC — `AlertEventR2dbcAdapter`

```java
@Repository
@RequiredArgsConstructor
public class AlertEventR2dbcAdapter implements AlertEventRepository {
    private final AlertEventR2dbcRepo r2dbcRepo;
    private final DatabaseClient databaseClient;

    @Override
    public Mono<AlertEvent> findActivaByProductoIdAndTipo(
            ProductoId productoId, TipoAlerta tipo) {
        return databaseClient.sql("""
                SELECT * FROM alert_events
                WHERE producto_id = :productoId
                  AND tipo_alerta = :tipo
                  AND estado = 'ACTIVA'
                ORDER BY created_at DESC
                LIMIT 1
                """)
            .bind("productoId", productoId.value())
            .bind("tipo", tipo.name())
            .map(AlertEventMapper::fromRow)
            .one();
    }

    @Override
    public Mono<Boolean> existsByProductoIdAndCreatedAtAfter(
            ProductoId productoId, Instant since) {
        return databaseClient.sql("""
                SELECT COUNT(*) > 0
                FROM alert_events
                WHERE producto_id = :productoId
                  AND created_at >= :since
                """)
            .bind("productoId", productoId.value())
            .bind("since", since)
            .map(row -> row.get(0, Boolean.class))
            .one()
            .defaultIfEmpty(false);
    }
}
```

### Kafka — `StockActualizadoConsumer`

```java
@Component
@RequiredArgsConstructor
public class StockActualizadoConsumer {
    private final EvaluarStockUseCase evaluarStockUseCase;
    private final ObjectMapper objectMapper;

    /**
     * Consume eventos StockActualizado de Kafka.
     * El acknowledgment se realiza SIEMPRE — incluso si la notificación falla.
     * La idempotencia de creación de alerta se maneja en el use case.
     */
    @KafkaListener(
        topics = "controlstock.inventory.stock-actualizado",
        groupId = "alert-service-stock-consumer",
        containerFactory = "kafkaListenerContainerFactory"
    )
    public Mono<Void> consume(ConsumerRecord<String, String> record) {
        return Mono.fromCallable(() ->
                objectMapper.readValue(record.value(), StockActualizadoEvent.class))
            .flatMap(evaluarStockUseCase::ejecutar)
            .doOnError(e -> log.error("Error procesando StockActualizado para key={}: {}",
                record.key(), e.getMessage()))
            .onErrorResume(e -> {
                // Error en deserialización o en BD: loguear, no relanzar (mensaje queda ACK)
                // Para errores no-transitorios se puede enviar al DLT manualmente
                return Mono.empty();
            });
    }
}
```

### WebClient — `IntegrationServiceNotificationAdapter`

```java
// src/main/java/com/controlstock/alert/infrastructure/webclient/IntegrationServiceNotificationAdapter.java
@Component
public class IntegrationServiceNotificationAdapter implements NotificationPort {

    private final WebClient webClient;

    public IntegrationServiceNotificationAdapter(
            @Value("${integration.service.base-url:http://integration-service.apps.svc.cluster.local:8089}")
            String baseUrl,
            WebClient.Builder webClientBuilder) {
        this.webClient = webClientBuilder
            .baseUrl(baseUrl)
            .defaultHeader(HttpHeaders.CONTENT_TYPE, MediaType.APPLICATION_JSON_VALUE)
            .build();
    }

    /**
     * Envía notificación a integration-service via POST /internal/notifications.
     * NO usa Kong — llamada directa por DNS interno K3s.
     * NO usa block() — totalmente reactivo.
     * Timeout de 5s para no bloquear el procesamiento de alertas.
     */
    @Override
    public Mono<Void> enviarNotificacion(NotificationRequest request) {
        return webClient.post()
            .uri("/internal/notifications")
            .bodyValue(request)
            .retrieve()
            .onStatus(HttpStatusCode::isError, response ->
                response.bodyToMono(String.class)
                    .flatMap(body -> Mono.error(new NotificationServiceException(
                        "integration-service retornó error: " + response.statusCode() + " - " + body)))
            )
            .bodyToMono(Void.class)
            .timeout(Duration.ofSeconds(5))
            .doOnSuccess(v -> log.debug("Notificación enviada para alerta {}", request.alertaId()))
            .doOnError(e -> log.error("Fallo enviando notificación para alerta {}: {}",
                request.alertaId(), e.getMessage()));
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

# URL de integration-service (override en test con WireMock)
integration:
  service:
    base-url: http://integration-service.apps.svc.cluster.local:8089
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
                .pathMatchers(HttpMethod.POST, "/alerts/{id}/reconocer")
                    .hasAnyRole("OPERADOR", "SUPERVISOR", "ADMIN")
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
| `GET` | `/alerts` | Listar alertas (filtros: `tipo`, `estado`, `productoId`) | Autenticado | 200 |
| `POST` | `/alerts/{id}/reconocer` | Reconocer alerta activa | OPERADOR, SUPERVISOR, ADMIN | 200 |

### Contratos de Request/Response

```json
// GET /alerts?estado=ACTIVA&tipo=BAJO_STOCK
// Response 200
{
  "content": [
    {
      "id": "uuid",
      "productoId": "uuid",
      "tipoAlerta": "BAJO_STOCK",
      "stockActual": 8.000,
      "umbral": 10.000,
      "estado": "ACTIVA",
      "createdAt": "2025-01-15T10:30:00Z",
      "updatedAt": "2025-01-15T10:30:00Z"
    }
  ],
  "page": 0,
  "size": 20,
  "totalElements": 1
}

// POST /alerts/{id}/reconocer
// Request: body vacío (solo autenticación JWT)
// Response 200
{
  "id": "uuid",
  "estado": "RECONOCIDA",
  "updatedAt": "2025-01-15T11:00:00Z"
}

// POST /alerts/{id}/reconocer — alerta ya reconocida (no ACTIVA)
// Response 409 Conflict
{
  "error": "ALERTA_NO_ACTIVA",
  "mensaje": "La alerta no puede reconocerse porque no está en estado ACTIVA",
  "alertaId": "uuid",
  "estadoActual": "RECONOCIDA"
}
```

### `@ExceptionHandler` en `GlobalExceptionHandler`

| Excepción | HTTP Status | Campo en body |
|-----------|-------------|---------------|
| `AlertaNoEncontradaException` | 404 | `alertaId` |
| `AlertaNoActivaException` | 409 | `alertaId`, `estadoActual` |
| `UmbralInvalidoException` | 400 | `error`, `mensaje` |
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
- WireMock (Testcontainers WireMock o NodePort 9999) para integration-service
```

### Capa de Dominio

| # | Test Class | Caso de prueba | Aserción |
|---|-----------|----------------|----------|
| D-01 | `AlertRuleTest` | `evaluarStock_stockPorDebajoDeMinimo_retornaBajoStock` | `Optional<BAJO_STOCK>` presente |
| D-02 | `AlertRuleTest` | `evaluarStock_stockExactamenteIgualAMinimo_retornaBajoStock` | **boundary**: `stock == stock_minimo` → `BAJO_STOCK` |
| D-03 | `AlertRuleTest` | `evaluarStock_stockUnoPorEncimaDeMinimo_retornaEmpty` | `Optional.empty()` — stock=11, minimo=10 → NORMAL |
| D-04 | `AlertRuleTest` | `evaluarStock_stockExactamenteIgualAMaximo_retornaSobrestock` | **boundary**: `stock == stock_maximo` → `SOBRESTOCK` |
| D-05 | `AlertRuleTest` | `evaluarStock_stockUnoPorDebajoDeMaximo_retornaEmpty` | `Optional.empty()` — stock=99, maximo=100 → NORMAL |
| D-06 | `AlertRuleTest` | `evaluarStock_stockPorEncimaDeMaximo_retornaSobrestock` | `Optional<SOBRESTOCK>` presente |
| D-07 | `AlertRuleTest` | `evaluarStock_reglaInactiva_retornaEmpty` | `activo == false` → siempre `Optional.empty()` |
| D-08 | `AlertRuleTest` | `crear_conMaximoMenorQueMinimo_lanzaExcepcion` | `UmbralInvalidoException` |
| D-09 | `AlertRuleTest` | `crear_conMinimoNegativo_lanzaExcepcion` | `UmbralInvalidoException` |
| D-10 | `AlertEventTest` | `reconocer_alertaActiva_cambiaEstado` | `estado == RECONOCIDA` |
| D-11 | `AlertEventTest` | `reconocer_alertaNoActiva_lanzaExcepcion` | `AlertaNoActivaException` |
| D-12 | `AlertEventTest` | `resolver_alertaActiva_cambiaEstadoResuelta` | `estado == RESUELTA` |
| D-13 | `AlertEventTest` | `resolver_alertaYaResuelta_esIdempotente` | No lanza excepción; `estado == RESUELTA` |

**Cobertura objetivo: dominio ≥ 90%**

Nota crítica: los tests D-02 y D-04 verifican las **condiciones de borde exactas** de los umbrales. El operador `<=` (no `<`) y `>=` (no `>`) es el invariante de negocio más importante de este dominio.

### Capa de Aplicación

| # | Test Class | Caso de prueba | Mock / Aserción |
|---|-----------|----------------|-----------------|
| A-01 | `EvaluarStockUseCaseTest` | `ejecutar_stockBajoMinimo_creaAlertaYNotifica` | `alertEventRepo.save(...)` llamado con `tipo == BAJO_STOCK`; `notificationPort.enviarNotificacion(...)` llamado |
| A-02 | `EvaluarStockUseCaseTest` | `ejecutar_stockIgualAMinimo_creaAlertaBajoStock` | Boundary: umbral exacto activa alerta |
| A-03 | `EvaluarStockUseCaseTest` | `ejecutar_stockNormal_noGeneraAlerta` | `alertEventRepo.save(...)` NO llamado |
| A-04 | `EvaluarStockUseCaseTest` | `ejecutar_falloNotificacion_noFallaElProcesamiento` | `notificationPort.enviarNotificacion(...)` retorna error; `StepVerifier` verifica `verifyComplete()` — NO `verifyError()` |
| A-05 | `EvaluarStockUseCaseTest` | `ejecutar_alertaActivaYaExiste_noCreaDuplicado` | `alertEventRepo.findActivaByProductoIdAndTipo(...)` retorna alerta existente; `alertEventRepo.save(...)` NO llamado segunda vez |
| A-06 | `EvaluarStockUseCaseTest` | `ejecutar_sinReglaDeAlerta_skipSinError` | `alertRuleRepo.findByProductoId(...)` retorna empty; `StepVerifier` verifica `verifyComplete()` |
| A-07 | `EvaluarStockUseCaseTest` | `ejecutar_stockVuelveANormal_resuelveAlertaActiva` | `alertEventRepo.findActivaByProductoIdAndTipo(...)` retorna alerta; `alerta.estado == RESUELTA` tras `save` |
| A-08 | `ReconocerAlertaUseCaseTest` | `ejecutar_alertaActiva_cambia_aReconocida` | `alertEventRepo.save(...)` con `estado == RECONOCIDA` |
| A-09 | `ReconocerAlertaUseCaseTest` | `ejecutar_alertaNoExiste_retorna404` | `expectError(AlertaNoEncontradaException.class)` |
| A-10 | `ReconocerAlertaUseCaseTest` | `ejecutar_alertaNoActiva_retorna409` | `expectError(AlertaNoActivaException.class)` |

**Cobertura objetivo: aplicación ≥ 85%**

### Capa de Infraestructura

| # | Test Class | Tipo | Caso de prueba |
|---|-----------|------|----------------|
| I-01 | `AlertRuleR2dbcAdapterTest` | `@DataR2dbcTest` + Testcontainers PG | `findByProductoId_existingRule_retornaUmbrale` |
| I-02 | `AlertRuleR2dbcAdapterTest` | `@DataR2dbcTest` + Testcontainers PG | `findByProductoId_noExiste_retornaEmpty` |
| I-03 | `AlertEventR2dbcAdapterTest` | `@DataR2dbcTest` + Testcontainers PG | `findActivaByProductoIdAndTipo_retornaSoloActiva` |
| I-04 | `StockActualizadoConsumerTest` | `@SpringBootTest` + Testcontainers PG + Kafka | `consume_stockBajoMinimo_creaAlertaEnBD` |
| I-05 | `StockActualizadoConsumerTest` | `@SpringBootTest` + Testcontainers PG + Kafka | `consume_falloNotificacion_mensajeKafkaSigueACK` — WireMock retorna 500; `verifyComplete()` en consumer |
| I-06 | `StockActualizadoConsumerTest` | `@SpringBootTest` + Testcontainers PG + Kafka | `consume_mensajeDuplicado_noCreaDosAlertas` — mismo `productoId+tipo` entregado 2 veces; solo 1 alerta en BD |
| I-07 | `IntegrationServiceNotificationAdapterTest` | `@SpringBootTest` + WireMock (Testcontainers) | `enviarNotificacion_success_retornaMono` — WireMock responde 200 |
| I-08 | `IntegrationServiceNotificationAdapterTest` | `@SpringBootTest` + WireMock (Testcontainers) | `enviarNotificacion_error500_retornaMonoError` — WireMock responde 500; Mono termina con `NotificationServiceException` |
| I-09 | `IntegrationServiceNotificationAdapterTest` | `@SpringBootTest` + WireMock (Testcontainers) | `enviarNotificacion_timeout_retornaMonoError` — WireMock introduce delay 6s (> timeout 5s); Mono termina con `TimeoutException` |

**Cobertura objetivo: infraestructura ≥ 80%**

### API REST

| # | Test Class | Tipo | Caso de prueba |
|---|-----------|------|----------------|
| R-01 | `AlertControllerTest` | `@WebFluxTest` | `GET /alerts → 200 con lista (vacía o con alertas)` |
| R-02 | `AlertControllerTest` | `@WebFluxTest` | `GET /alerts?estado=ACTIVA → 200 filtrando solo ACTIVAS` |
| R-03 | `AlertControllerTest` | `@WebFluxTest` | `GET /alerts?tipo=BAJO_STOCK → 200 filtrando solo BAJO_STOCK` |
| R-04 | `AlertControllerTest` | `@WebFluxTest` | `POST /alerts/{id}/reconocer con rol OPERADOR → 200` |
| R-05 | `AlertControllerTest` | `@WebFluxTest` | `POST /alerts/{id}/reconocer alerta no ACTIVA → 409` |
| R-06 | `AlertControllerTest` | `@WebFluxTest` | `POST /alerts/{id}/reconocer sin token → 401` |
| R-07 | `AlertControllerTest` | `@WebFluxTest` | `GET /alerts sin token → 401` |

### Configuración Testcontainers con WireMock

```java
// src/test/java/com/controlstock/alert/infrastructure/BaseIntegrationTest.java
@Testcontainers
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
public abstract class BaseIntegrationTest {

    @Container
    static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:16-alpine")
        .withDatabaseName("controlstock_alert_test")
        .withInitScript("db/schema-alert.sql");

    @Container
    static KafkaContainer kafka = new KafkaContainer(
        DockerImageName.parse("confluentinc/cp-kafka:7.6.0"));

    // WireMock como Testcontainers para simular integration-service
    @Container
    static GenericContainer<?> wireMock = new GenericContainer<>("wiremock/wiremock:3.3.1")
        .withExposedPorts(8080)
        .withCommand("--port", "8080", "--verbose");

    @DynamicPropertySource
    static void configureProperties(DynamicPropertyRegistry registry) {
        registry.add("spring.r2dbc.url",
            () -> "r2dbc:postgresql://" + postgres.getHost() + ":" +
                  postgres.getFirstMappedPort() + "/controlstock_alert_test");
        registry.add("spring.r2dbc.username", postgres::getUsername);
        registry.add("spring.r2dbc.password", postgres::getPassword);
        registry.add("spring.kafka.bootstrap-servers", kafka::getBootstrapServers);
        // Override URL de integration-service con WireMock
        registry.add("integration.service.base-url",
            () -> "http://" + wireMock.getHost() + ":" + wireMock.getFirstMappedPort());
    }

    // Helper para configurar WireMock stubs en cada test
    protected WireMock wireMockClient() {
        return new WireMock(wireMock.getHost(), wireMock.getFirstMappedPort());
    }
}

// Ejemplo de configuración WireMock en test I-07
@Test
void enviarNotificacion_success_retornaMono() {
    wireMockClient().register(
        post(urlEqualTo("/internal/notifications"))
            .willReturn(aResponse()
                .withStatus(200)
                .withHeader("Content-Type", "application/json")
                .withBody("{}")
            )
    );

    StepVerifier.create(adapter.enviarNotificacion(notifRequest))
        .verifyComplete();

    wireMockClient().verifyThat(
        postRequestedFor(urlEqualTo("/internal/notifications"))
            .withHeader("Content-Type", containing("application/json"))
    );
}

// Ejemplo de test de timeout I-09
@Test
void enviarNotificacion_timeout_retornaMonoError() {
    wireMockClient().register(
        post(urlEqualTo("/internal/notifications"))
            .willReturn(aResponse()
                .withStatus(200)
                .withFixedDelay(6000)  // 6 segundos > timeout de 5s
            )
    );

    StepVerifier.create(adapter.enviarNotificacion(notifRequest))
        .expectError(TimeoutException.class)
        .verify(Duration.ofSeconds(10));
}
```

---

## Criterios de Aceptación

| # | Criterio | Verificación |
|---|---------|-------------|
| AC-01 | Al recibir `StockActualizado` con `stock_actual <= stock_mínimo`, se crea un `AlertEvent` de tipo `BAJO_STOCK` en BD independientemente del resultado de la notificación | Test I-04; inspección de `alert_events` en PostgreSQL |
| AC-02 | Al recibir `StockActualizado` con `stock_actual == stock_mínimo` (exactamente igual al umbral), se genera `BAJO_STOCK` — condición de borde inclusiva | Test I-04 con stock exacto al umbral |
| AC-03 | Al recibir `StockActualizado` con `stock_actual >= stock_máximo` (incluido), se crea `AlertEvent` de tipo `SOBRESTOCK` | Test D-04, I-04 |
| AC-04 | Si `integration-service` falla (HTTP 500, timeout, o red), el mensaje Kafka recibe ACK correctamente — el `AlertEvent` queda `ACTIVA` y el error queda loqueado | Test I-05 con WireMock retornando 500 |
| AC-05 | Si `StockActualizado` es reentregado para el mismo `productoId+tipo` con alerta ya `ACTIVA`, **no se crea una segunda alerta** (idempotencia de consumo) | Test I-06 |
| AC-06 | La llamada a `integration-service` usa **WebClient** (reactivo, no-blocking) — nunca `block()` ni `RestTemplate` | Revisión de código + BlockHound en test suite |
| AC-07 | La llamada a `integration-service` es **directa via DNS interno K3s** (`integration-service.apps.svc.cluster.local`) — no pasa por Kong | Inspección de configuración `application.yml` + test I-07 |
| AC-08 | `POST /alerts/{id}/reconocer` con rol `OPERADOR` devuelve 200 y `estado: RECONOCIDA` | Test R-04 |
| AC-09 | `POST /alerts/{id}/reconocer` sobre alerta no-`ACTIVA` devuelve **HTTP 409** con `estadoActual` en body | Test R-05 |
| AC-10 | Cobertura: Dominio ≥ 90%, Aplicación ≥ 85%, Infraestructura ≥ 80% | JaCoCo en pipeline Jenkins |
| AC-11 | `GET /actuator/health/readiness` retorna `{ "status": "UP" }` con PostgreSQL y Kafka como health indicators | Verificación manual en K3s |
| AC-12 | Toda la cadena reactiva usa `StepVerifier`; ausencia de `block()` verificada con `BlockHound` en test suite | BlockHound activo en `@SpringBootTest` |
