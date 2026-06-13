# Etapa 3b — Microservicio: Catalog Service (BC-02)

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

El **Catalog Service** (Bounded Context BC-02) es el microservicio responsable de la gestión del catálogo de productos y categorías de ControlStock. Es el **segundo microservicio en implementarse** dado que `Producto` es la entidad central del sistema: todos los demás bounded contexts (inventory, adjustment, alert) dependen de la existencia de productos en el catálogo.

### Responsabilidades del servicio

| Responsabilidad | Descripción |
|----------------|-------------|
| **Gestión de categorías** | Crear, actualizar y consultar categorías de productos |
| **Gestión de productos** | Crear, actualizar, consultar y desactivar productos |
| **Validación de invariantes** | Garantizar `stock_mínimo < stock_máximo` en cada producto |
| **Integridad referencial** | Impedir la desactivación de categorías con productos activos |
| **Unicidad de código** | Código de producto único dentro del catálogo |
| **Publicación de eventos de dominio** | Publicar `ProductoCreado`, `ProductoActualizado`, `ProductoInactivado` mediante Transactional Outbox → Kafka |
| **Proyección de lectura** | Consumir sus propios eventos y mantener la colección `productos` en MongoDB `controlstock_readmodel` |

### Lo que el servicio NO hace

| Restricción | Justificación |
|-------------|---------------|
| No gestiona stock físico | El stock es responsabilidad de `inventory-service` (BC-03) |
| No participa en sagas | No hay flujos distribuidos que involucren el catálogo |
| No tiene dependencias REST de otros servicios de dominio | Solo depende de Keycloak para validación de token |
| No gestiona precios ni proveedores directamente | Son responsabilidad de `supplier-service` (BC-06) |

### Bounded Context BC-02

```
┌──────────────────────────────────────────────────────────────────┐
│                    Catalog Service (BC-02)                       │
│                                                                  │
│  ┌────────────────┐    ┌──────────────────────────────────────┐ │
│  │   categorias   │    │             productos                │ │
│  └────────────────┘    │  - código (UNIQUE)                   │ │
│          │             │  - stock_minimo < stock_maximo ←INV  │ │
│          └─────────────┤  - estado IN (ACTIVO, INACTIVO)      │ │
│                        └──────────────────────────────────────┘ │
│                                         │                        │
│                                         ▼                        │
│                              ┌────────────────────┐             │
│                              │   outbox (R2DBC)    │             │
│                              │   status: PENDING   │             │
│                              └─────────┬──────────┘             │
│                                        │                         │
│             ┌──────────────────────────┘                         │
│             │  Outbox Relay (Scheduled)                          │
│             │  Reads PENDING → Kafka → PUBLISHED                 │
│             └──────────────────────────────────────────────────┐ │
└─────────────────────────────────────────────────────────────────┘
             │                                         │
             ▼ (produce)                               ▼ (consume)
   ┌──────────────────────┐              ┌───────────────────────┐
   │  Apache Kafka        │              │  MongoDB Projection   │
   │  controlstock.catalog│◄─────────────│  Consumer (BC-02)     │
   │  .producto-*         │              │  → productos coll.    │
   └──────────────────────┘              └───────────────────────┘
```

### Base de datos

- **PostgreSQL 16** — schema `controlstock_catalog` (escritura + outbox)
- **MongoDB 7** — base de datos `controlstock_readmodel`, colección `productos` (lectura)
- **Tecnología de acceso**: Spring Data R2DBC (PostgreSQL reactivo) + Reactive MongoDB Driver

---

## Prerrequisitos

| Prerrequisito | Documento de referencia | Verificación |
|--------------|------------------------|-------------|
| Etapa 0 — Infraestructura base completa | `DEV-ControlStock-00-infrastructure.md` | K3s corriendo |
| Etapa 0c — Observabilidad configurada | `DEV-ControlStock-0c-observability.md` | Prometheus activo |
| Etapa 1 — Bases de datos aprovisionadas | `DEV-ControlStock-01-databases.md` | PostgreSQL `controlstock_catalog` + MongoDB `controlstock_readmodel` con colecciones |
| Etapa 2 — Scaffold generado | `DEV-ControlStock-02-scaffold.md` | Proyecto Maven generado |
| Etapa 2b — Pipeline CI/CD configurado | `DEV-ControlStock-02b-cicd.md` | Job `catalog-service` activo |
| **Etapa 3a — IAM Service corriendo** | `DEV-ControlStock-03-ms-iam-service.md` | Keycloak emitiendo tokens JWT válidos para realm `controlstock` |
| Kafka (Strimzi KRaft) corriendo | Etapa 0 | Topics `controlstock.catalog.*` creados |

### Verificación de prerrequisitos

```bash
# Verificar schema PostgreSQL catalog
kubectl exec -n databases deploy/postgresql -- psql \
  -U controlstock_catalog -d controlstock_catalog \
  -c "\dt" | grep -E "categorias|productos|outbox"

# Verificar MongoDB y colección
kubectl exec -n databases deploy/mongodb -- mongosh \
  --eval "use controlstock_readmodel; db.getCollectionNames()"

# Verificar topics Kafka
kubectl exec -n kafka deploy/kafka -- \
  kafka-topics.sh --list --bootstrap-server kafka:9092 \
  | grep "controlstock.catalog"
# Salida esperada:
# controlstock.catalog.producto-creado
# controlstock.catalog.producto-actualizado
# controlstock.catalog.producto-inactivado

# Verificar IAM Service / Keycloak token
curl -s -X POST \
  "http://<VPS_IP>:8180/realms/controlstock/protocol/openid-connect/token" \
  -d "client_id=catalog-service-client&grant_type=client_credentials&client_secret=<secret>" \
  | jq '.access_token' | head -c 50
```

---

## Ciclo de Desarrollo Incremental en K3s VPS dev

```
┌─────────────────────────────────────────────────────┐
│              Ciclo de Desarrollo TDD                │
│                                                     │
│  1. Escribir test RED (falla esperada)              │
│         │                                           │
│         ▼                                           │
│  2. Implementar mínimo código GREEN                 │
│         │                                           │
│         ▼                                           │
│  3. REFACTOR — mejorar diseño                       │
│         │                                           │
│         ▼                                           │
│  4. git push → Gitea webhook → Jenkins pipeline     │
│         │                                           │
│         ▼                                           │
│  5. bumpImageTag → ArgoCD sync → K3s pod            │
│         │                                           │
│         ▼                                           │
│  6. Verificar /actuator/health + prueba manual      │
│         │                                           │
│  Condición mínima para primer deploy:               │
│  - Dominio compila; contexto Spring arranca         │
│  - GET /actuator/health/readiness → 200             │
└─────────────────────────────────────────────────────┘
```

### Orden de implementación incremental

| Incremento | Capa | Contenido | Condición de avance |
|-----------|------|-----------|-------------------|
| **I-1** | Dominio | Entidades `Categoria`, `Producto`; VOs; invariante `stock_minimo < stock_maximo` | Tests dominio GREEN |
| **I-2** | Dominio | Eventos de dominio (`ProductoCreado`, `ProductoActualizado`, `ProductoInactivado`) | Tests eventos GREEN |
| **I-3** | Aplicación | Use cases (crear/actualizar categoría y producto) | Tests aplicación GREEN |
| **I-4** | Infraestructura | R2DBC adapters para `categorias`, `productos`, `outbox` | Tests Testcontainers (PostgreSQL) GREEN |
| **I-5** | Infraestructura | `OutboxRelay` (scheduler R2DBC → Kafka) | Tests Testcontainers (PostgreSQL + Kafka) GREEN |
| **I-6** | Infraestructura | MongoDB projection consumer | Tests Testcontainers (MongoDB + Kafka) GREEN |
| **I-7** | Aplicación | Use cases de desactivación + consultas paginadas | Tests aplicación GREEN |
| **I-8** | API REST | Endpoints completos + @ExceptionHandler | Tests @WebFluxTest GREEN |
| **I-9** | Integración | Tests E2E en K3s (flujo completo: POST → Kafka → MongoDB) | Suite de humo GREEN |

---

## Capa de Dominio

### Entidades

#### `Categoria`

```java
// src/main/java/com/controlstock/catalog/domain/model/Categoria.java
public class Categoria {
    private final CategoriaId id;
    private final CodigoCategoria codigo;  // VARCHAR(20) UNIQUE
    private String nombre;
    private String descripcion;
    private EstadoCategoria estado;
    private final Instant createdAt;
    private Instant updatedAt;

    // Invariante: no se puede desactivar si tiene productos activos
    // Esta regla se verifica en el use case (requiere consulta al repo)

    public void desactivar() {
        if (this.estado == EstadoCategoria.INACTIVO) {
            throw new CategoriaYaInactivaException(this.id);
        }
        this.estado = EstadoCategoria.INACTIVO;
        this.updatedAt = Instant.now();
    }

    public void actualizar(String nuevoNombre, String nuevaDescripcion) {
        this.nombre = Objects.requireNonNull(nuevoNombre);
        this.descripcion = nuevaDescripcion;
        this.updatedAt = Instant.now();
    }
}
```

#### `Producto`

La invariante central de este bounded context es `stock_minimo < stock_maximo`.

```java
// src/main/java/com/controlstock/catalog/domain/model/Producto.java
public class Producto {
    private final ProductoId id;
    private final CodigoProducto codigo;  // VARCHAR(50) UNIQUE
    private String nombre;
    private String descripcion;
    private final CategoriaId categoriaId;
    private StockMinimo stockMinimo;
    private StockMaximo stockMaximo;
    private EstadoProducto estado;
    private final Instant createdAt;
    private Instant updatedAt;

    // Invariante central: stock_minimo < stock_maximo
    private static void validarStock(BigDecimal minimo, BigDecimal maximo) {
        if (minimo == null || maximo == null) {
            throw new StockNuloException();
        }
        if (minimo.compareTo(BigDecimal.ZERO) < 0) {
            throw new StockMinimoNegativoException(minimo);
        }
        if (maximo.compareTo(minimo) <= 0) {
            throw new StockMaximoMenorOIgualMinimoException(minimo, maximo);
        }
    }

    public static Producto crear(
            CodigoProducto codigo,
            String nombre,
            String descripcion,
            CategoriaId categoriaId,
            BigDecimal stockMinimo,
            BigDecimal stockMaximo) {
        validarStock(stockMinimo, stockMaximo);
        return new Producto(
            new ProductoId(UUID.randomUUID()),
            codigo, nombre, descripcion, categoriaId,
            new StockMinimo(stockMinimo),
            new StockMaximo(stockMaximo),
            EstadoProducto.ACTIVO,
            Instant.now(), Instant.now()
        );
    }

    public List<DomainEvent> actualizar(
            String nuevoNombre,
            String nuevaDescripcion,
            BigDecimal nuevoStockMinimo,
            BigDecimal nuevoStockMaximo) {
        validarStock(nuevoStockMinimo, nuevoStockMaximo);
        this.nombre = nuevoNombre;
        this.descripcion = nuevaDescripcion;
        this.stockMinimo = new StockMinimo(nuevoStockMinimo);
        this.stockMaximo = new StockMaximo(nuevoStockMaximo);
        this.updatedAt = Instant.now();
        return List.of(new ProductoActualizado(this));
    }

    public List<DomainEvent> inactivar() {
        if (this.estado == EstadoProducto.INACTIVO) {
            throw new ProductoYaInactivoException(this.id);
        }
        this.estado = EstadoProducto.INACTIVO;
        this.updatedAt = Instant.now();
        return List.of(new ProductoInactivado(this));
    }
}
```

### Value Objects

| Value Object | Validaciones | Clase |
|-------------|-------------|-------|
| `CodigoProducto` | No nulo, no vacío, máx 50 chars, solo alfanumérico+guión | `com.controlstock.catalog.domain.vo.CodigoProducto` |
| `CodigoCategoria` | No nulo, no vacío, máx 20 chars, solo alfanumérico+guión | `com.controlstock.catalog.domain.vo.CodigoCategoria` |
| `StockMinimo` | `>= 0`, no nulo (BigDecimal con 3 decimales) | `com.controlstock.catalog.domain.vo.StockMinimo` |
| `StockMaximo` | `> 0`, no nulo (BigDecimal con 3 decimales) | `com.controlstock.catalog.domain.vo.StockMaximo` |
| `ProductoId` | UUID no nulo | `com.controlstock.catalog.domain.vo.ProductoId` |
| `CategoriaId` | UUID no nulo | `com.controlstock.catalog.domain.vo.CategoriaId` |

```java
// StockMinimo Value Object
public record StockMinimo(BigDecimal value) {
    public StockMinimo {
        Objects.requireNonNull(value, "stock_minimo no puede ser nulo");
        if (value.compareTo(BigDecimal.ZERO) < 0) {
            throw new StockMinimoNegativoException(value);
        }
        value = value.setScale(3, RoundingMode.HALF_UP);
    }
}

// StockMaximo Value Object
public record StockMaximo(BigDecimal value) {
    public StockMaximo {
        Objects.requireNonNull(value, "stock_maximo no puede ser nulo");
        if (value.compareTo(BigDecimal.ZERO) <= 0) {
            throw new StockMaximoNonPositivoException(value);
        }
        value = value.setScale(3, RoundingMode.HALF_UP);
    }
}
```

### Eventos de Dominio

```java
// Interfaz base de evento de dominio
public interface DomainEvent {
    String getEventType();
    String getAggregateType();
    UUID getAggregateId();
    Instant getOccurredAt();
    String getTopic();
}

// ProductoCreado
public record ProductoCreado(
    UUID productoId,
    String codigo,
    String nombre,
    UUID categoriaId,
    BigDecimal stockMinimo,
    BigDecimal stockMaximo,
    Instant occurredAt
) implements DomainEvent {
    public ProductoCreado(Producto producto) {
        this(producto.getId().value(), producto.getCodigo().value(),
             producto.getNombre(), producto.getCategoriaId().value(),
             producto.getStockMinimo().value(), producto.getStockMaximo().value(),
             Instant.now());
    }

    @Override public String getEventType() { return "ProductoCreado"; }
    @Override public String getAggregateType() { return "Producto"; }
    @Override public UUID getAggregateId() { return productoId; }
    @Override public Instant getOccurredAt() { return occurredAt; }
    @Override public String getTopic() { return "controlstock.catalog.producto-creado"; }
}

// ProductoActualizado
public record ProductoActualizado(
    UUID productoId,
    String codigo,
    String nombre,
    BigDecimal stockMinimo,
    BigDecimal stockMaximo,
    Instant occurredAt
) implements DomainEvent {
    @Override public String getEventType() { return "ProductoActualizado"; }
    @Override public String getTopic() { return "controlstock.catalog.producto-actualizado"; }
    // ...
}

// ProductoInactivado
public record ProductoInactivado(
    UUID productoId,
    String codigo,
    Instant occurredAt
) implements DomainEvent {
    @Override public String getEventType() { return "ProductoInactivado"; }
    @Override public String getTopic() { return "controlstock.catalog.producto-inactivado"; }
    // ...
}
```

### Topics de Kafka

| Evento | Topic | Partitions | Retention |
|--------|-------|-----------|-----------|
| `ProductoCreado` | `controlstock.catalog.producto-creado` | 3 | 7 días |
| `ProductoActualizado` | `controlstock.catalog.producto-actualizado` | 3 | 7 días |
| `ProductoInactivado` | `controlstock.catalog.producto-inactivado` | 3 | 7 días |

### Puertos (interfaces de dominio)

```java
// Puerto: CategoriaRepository
public interface CategoriaRepository {
    Mono<Categoria> save(Categoria categoria);
    Mono<Categoria> findById(CategoriaId id);
    Mono<Categoria> findByCodigo(CodigoCategoria codigo);
    Flux<Categoria> findAll(Pageable pageable);
    Mono<Boolean> existsByCodigo(CodigoCategoria codigo);
    Mono<Boolean> tieneProductosActivos(CategoriaId id);
}

// Puerto: ProductoRepository
public interface ProductoRepository {
    Mono<Producto> save(Producto producto);
    Mono<Producto> findById(ProductoId id);
    Mono<Producto> findByCodigo(CodigoProducto codigo);
    Flux<Producto> findAll(ProductoFilter filter, Pageable pageable);
    Mono<Boolean> existsByCodigo(CodigoProducto codigo);
}

// Puerto: OutboxRepository
public interface OutboxRepository {
    Mono<Void> save(DomainEvent event);
    Flux<OutboxEntry> findPending(int limit);
    Mono<Void> markAsPublished(UUID outboxId);
    Mono<Void> markAsFailed(UUID outboxId);
}

// Puerto: EventoPublisher (Kafka)
public interface EventoPublisher {
    Mono<Void> publish(String topic, String key, String payload);
}

// Puerto: ProductoReadModelRepository (MongoDB)
public interface ProductoReadModelRepository {
    Mono<Void> save(ProductoDocument document);
    Mono<Void> updateEstado(UUID productoId, String estado);
}
```

### Excepciones de dominio

| Excepción | Trigger |
|-----------|---------|
| `StockMaximoMenorOIgualMinimoException` | `stock_maximo <= stock_minimo` (invariante central) |
| `StockMinimoNegativoException` | `stock_minimo < 0` |
| `ProductoYaInactivoException` | Inactivar producto ya inactivo |
| `CodigoProductoDuplicadoException` | Código de producto ya existe |
| `CategoriaYaInactivaException` | Desactivar categoría ya inactiva |
| `CategoriaConProductosActivosException` | Desactivar categoría con productos activos |
| `ProductoNoEncontradoException` | Producto no encontrado por ID |
| `CategoriaNoEncontradaException` | Categoría no encontrada por ID |

---

## Capa de Aplicación

### Use Cases

#### `CrearProductoUseCase`

```java
@UseCase
@Transactional
public class CrearProductoUseCase {

    private final ProductoRepository productoRepository;
    private final CategoriaRepository categoriaRepository;
    private final OutboxRepository outboxRepository;

    public Mono<ProductoDTO> ejecutar(CrearProductoCommand command) {
        return Mono.zip(
            productoRepository.existsByCodigo(new CodigoProducto(command.codigo()))
                .flatMap(exists -> {
                    if (exists) return Mono.error(
                        new CodigoProductoDuplicadoException(command.codigo()));
                    return Mono.just(false);
                }),
            categoriaRepository.findById(new CategoriaId(command.categoriaId()))
                .switchIfEmpty(Mono.error(
                    new CategoriaNoEncontradaException(new CategoriaId(command.categoriaId()))))
        ).flatMap(tuple -> {
            // Esto llama a Producto.crear() que valida la invariante internamente
            Producto producto = Producto.crear(
                new CodigoProducto(command.codigo()),
                command.nombre(),
                command.descripcion(),
                new CategoriaId(command.categoriaId()),
                command.stockMinimo(),
                command.stockMaximo()
            );
            ProductoCreado event = new ProductoCreado(producto);
            return productoRepository.save(producto)
                .flatMap(saved -> outboxRepository.save(event).thenReturn(saved));
        })
        .map(ProductoMapper::toDTO);
    }
}
```

#### `ActualizarProductoUseCase`

```java
@UseCase
@Transactional
public class ActualizarProductoUseCase {

    private final ProductoRepository productoRepository;
    private final OutboxRepository outboxRepository;

    public Mono<ProductoDTO> ejecutar(ProductoId id, ActualizarProductoCommand command) {
        return productoRepository.findById(id)
            .switchIfEmpty(Mono.error(new ProductoNoEncontradoException(id)))
            .flatMap(producto -> {
                // actualizar() valida invariante y retorna eventos
                List<DomainEvent> events = producto.actualizar(
                    command.nombre(),
                    command.descripcion(),
                    command.stockMinimo(),
                    command.stockMaximo()
                );
                return productoRepository.save(producto)
                    .flatMap(saved ->
                        Flux.fromIterable(events)
                            .flatMap(outboxRepository::save)
                            .then(Mono.just(saved))
                    );
            })
            .map(ProductoMapper::toDTO);
    }
}
```

#### `InactivarProductoUseCase`

```java
@UseCase
@Transactional
public class InactivarProductoUseCase {

    private final ProductoRepository productoRepository;
    private final OutboxRepository outboxRepository;

    public Mono<Void> ejecutar(ProductoId id) {
        return productoRepository.findById(id)
            .switchIfEmpty(Mono.error(new ProductoNoEncontradoException(id)))
            .flatMap(producto -> {
                List<DomainEvent> events = producto.inactivar();
                return productoRepository.save(producto)
                    .flatMap(saved ->
                        Flux.fromIterable(events)
                            .flatMap(outboxRepository::save)
                            .then()
                    );
            });
    }
}
```

#### `CrearCategoriaUseCase`

```java
@UseCase
@Transactional
public class CrearCategoriaUseCase {

    private final CategoriaRepository categoriaRepository;

    public Mono<CategoriaDTO> ejecutar(CrearCategoriaCommand command) {
        return categoriaRepository.existsByCodigo(new CodigoCategoria(command.codigo()))
            .flatMap(exists -> {
                if (exists) return Mono.error(
                    new CodigoCategoriaDuplicadoException(command.codigo()));
                Categoria categoria = Categoria.crear(
                    new CodigoCategoria(command.codigo()),
                    command.nombre(),
                    command.descripcion()
                );
                return categoriaRepository.save(categoria);
            })
            .map(CategoriaMapper::toDTO);
    }
}
```

#### `DesactivarCategoriaUseCase`

```java
@UseCase
@Transactional
public class DesactivarCategoriaUseCase {

    private final CategoriaRepository categoriaRepository;

    public Mono<Void> ejecutar(CategoriaId id) {
        return categoriaRepository.findById(id)
            .switchIfEmpty(Mono.error(new CategoriaNoEncontradaException(id)))
            .flatMap(categoria ->
                categoriaRepository.tieneProductosActivos(id)
                    .flatMap(tieneActivos -> {
                        if (tieneActivos) {
                            return Mono.error(
                                new CategoriaConProductosActivosException(id));
                        }
                        categoria.desactivar();
                        return categoriaRepository.save(categoria).then();
                    })
            );
    }
}
```

#### `ListarProductosUseCase`

```java
@UseCase
public class ListarProductosUseCase {

    private final ProductoRepository productoRepository;

    public Flux<ProductoDTO> ejecutar(ProductoFilter filter, Pageable pageable) {
        return productoRepository.findAll(filter, pageable)
            .map(ProductoMapper::toDTO);
    }
}
```

### DTOs de Aplicación

#### Comandos

```java
// Crear producto
public record CrearProductoCommand(
    String codigo,
    String nombre,
    String descripcion,
    UUID categoriaId,
    BigDecimal stockMinimo,
    BigDecimal stockMaximo
) {}

// Actualizar producto
public record ActualizarProductoCommand(
    String nombre,
    String descripcion,
    BigDecimal stockMinimo,
    BigDecimal stockMaximo
) {}

// Crear categoría
public record CrearCategoriaCommand(
    String codigo,
    String nombre,
    String descripcion
) {}

// Filtro de productos
public record ProductoFilter(
    Optional<UUID> categoriaId,
    Optional<String> estado
) {}
```

#### DTOs de respuesta

```java
// ProductoDTO
public record ProductoDTO(
    UUID id,
    String codigo,
    String nombre,
    String descripcion,
    UUID categoriaId,
    String categoriaNombre,
    BigDecimal stockMinimo,
    BigDecimal stockMaximo,
    String estado,
    Instant createdAt,
    Instant updatedAt
) {}

// CategoriaDTO
public record CategoriaDTO(
    UUID id,
    String codigo,
    String nombre,
    String descripcion,
    String estado,
    Instant createdAt,
    Instant updatedAt
) {}
```

---

## Capa de Infraestructura

### Adaptadores R2DBC (PostgreSQL)

#### `ProductoR2dbcAdapter`

```java
@Repository
@RequiredArgsConstructor
public class ProductoR2dbcAdapter implements ProductoRepository {

    private final DatabaseClient databaseClient;

    @Override
    public Mono<Producto> save(Producto producto) {
        return databaseClient.sql("""
            INSERT INTO productos (
              id, codigo, nombre, descripcion, categoria_id,
              stock_minimo, stock_maximo, estado, created_at, updated_at
            ) VALUES (
              :id, :codigo, :nombre, :descripcion, :categoriaId,
              :stockMinimo, :stockMaximo, :estado, :createdAt, :updatedAt
            )
            ON CONFLICT (id) DO UPDATE SET
              nombre = EXCLUDED.nombre,
              descripcion = EXCLUDED.descripcion,
              stock_minimo = EXCLUDED.stock_minimo,
              stock_maximo = EXCLUDED.stock_maximo,
              estado = EXCLUDED.estado,
              updated_at = EXCLUDED.updated_at
            RETURNING *
            """)
            .bind("id", producto.getId().value())
            .bind("codigo", producto.getCodigo().value())
            .bind("stockMinimo", producto.getStockMinimo().value())
            .bind("stockMaximo", producto.getStockMaximo().value())
            // ... otros binds
            .map(row -> ProductoRowMapper.map(row))
            .one();
    }

    @Override
    public Flux<Producto> findAll(ProductoFilter filter, Pageable pageable) {
        StringBuilder sql = new StringBuilder("SELECT * FROM productos WHERE 1=1");
        Map<String, Object> params = new HashMap<>();

        filter.categoriaId().ifPresent(cId -> {
            sql.append(" AND categoria_id = :categoriaId");
            params.put("categoriaId", cId);
        });
        filter.estado().ifPresent(est -> {
            sql.append(" AND estado = :estado");
            params.put("estado", est);
        });
        sql.append(" ORDER BY created_at DESC LIMIT :limit OFFSET :offset");
        params.put("limit", pageable.getPageSize());
        params.put("offset", pageable.getOffset());

        DatabaseClient.GenericExecuteSpec spec = databaseClient.sql(sql.toString());
        for (Map.Entry<String, Object> entry : params.entrySet()) {
            spec = spec.bind(entry.getKey(), entry.getValue());
        }
        return spec.map(row -> ProductoRowMapper.map(row)).all();
    }
}
```

#### `OutboxR2dbcAdapter`

```java
@Repository
@RequiredArgsConstructor
public class OutboxR2dbcAdapter implements OutboxRepository {

    private final DatabaseClient databaseClient;
    private final ObjectMapper objectMapper;

    @Override
    public Mono<Void> save(DomainEvent event) {
        return Mono.fromCallable(() -> objectMapper.writeValueAsString(event))
            .flatMap(payload -> databaseClient.sql("""
                INSERT INTO outbox (
                  id, aggregate_type, aggregate_id, event_type,
                  payload, topic, created_at, status
                ) VALUES (
                  :id, :aggregateType, :aggregateId, :eventType,
                  :payload::jsonb, :topic, :createdAt, 'PENDING'
                )
                """)
                .bind("id", UUID.randomUUID())
                .bind("aggregateType", event.getAggregateType())
                .bind("aggregateId", event.getAggregateId())
                .bind("eventType", event.getEventType())
                .bind("payload", payload)
                .bind("topic", event.getTopic())
                .bind("createdAt", Instant.now())
                .then()
            );
    }

    @Override
    public Flux<OutboxEntry> findPending(int limit) {
        return databaseClient.sql("""
            SELECT * FROM outbox
            WHERE status = 'PENDING'
            ORDER BY created_at ASC
            LIMIT :limit
            FOR UPDATE SKIP LOCKED
            """)
            .bind("limit", limit)
            .map(row -> OutboxRowMapper.map(row))
            .all();
    }

    @Override
    public Mono<Void> markAsPublished(UUID outboxId) {
        return databaseClient.sql("""
            UPDATE outbox
            SET status = 'PUBLISHED', published_at = :publishedAt
            WHERE id = :id
            """)
            .bind("publishedAt", Instant.now())
            .bind("id", outboxId)
            .then();
    }

    @Override
    public Mono<Void> markAsFailed(UUID outboxId) {
        return databaseClient.sql("""
            UPDATE outbox SET status = 'FAILED' WHERE id = :id
            """)
            .bind("id", outboxId)
            .then();
    }
}
```

### Outbox Relay (Scheduled)

El relay es un proceso programado que lee entradas `PENDING` de la tabla `outbox`, las publica a Kafka y actualiza el estado a `PUBLISHED`. Usa `FOR UPDATE SKIP LOCKED` para permitir múltiples instancias del servicio sin duplicados.

```java
@Component
@RequiredArgsConstructor
@Slf4j
public class OutboxRelay {

    private final OutboxRepository outboxRepository;
    private final EventoPublisher eventoPublisher;

    @Scheduled(fixedDelay = 1000)  // Cada 1 segundo
    public void relay() {
        outboxRepository.findPending(50)
            .flatMap(entry ->
                eventoPublisher.publish(
                    entry.getTopic(),
                    entry.getAggregateId().toString(),
                    entry.getPayload()
                )
                .then(outboxRepository.markAsPublished(entry.getId()))
                .onErrorResume(error -> {
                    log.error("Error publicando outbox entry {}: {}",
                        entry.getId(), error.getMessage());
                    return outboxRepository.markAsFailed(entry.getId());
                })
            )
            .subscribe();
    }
}
```

### Adaptador Kafka (`KafkaEventoPublisher`)

```java
@Component
@RequiredArgsConstructor
public class KafkaEventoPublisher implements EventoPublisher {

    private final ReactiveKafkaProducerTemplate<String, String> kafkaTemplate;

    @Override
    public Mono<Void> publish(String topic, String key, String payload) {
        return kafkaTemplate.send(topic, key, payload)
            .doOnNext(result -> log.debug("Evento publicado a {}: offset={}",
                topic, result.recordMetadata().offset()))
            .doOnError(error -> log.error("Error publicando a Kafka topic {}: {}",
                topic, error.getMessage()))
            .then();
    }
}
```

### Adaptador MongoDB — Proyección de Lectura

#### `ProductoMongoAdapter`

```java
@Repository
@RequiredArgsConstructor
public class ProductoMongoAdapter implements ProductoReadModelRepository {

    private final ReactiveMongoTemplate mongoTemplate;

    @Override
    public Mono<Void> save(ProductoDocument document) {
        return mongoTemplate.save(document, "productos").then();
    }

    @Override
    public Mono<Void> updateEstado(UUID productoId, String estado) {
        Query query = Query.query(Criteria.where("_id").is(productoId.toString()));
        Update update = Update.update("estado", estado)
            .set("updatedAt", Instant.now());
        return mongoTemplate.updateFirst(query, update, ProductoDocument.class, "productos")
            .then();
    }
}
```

#### `ProductoDocument` (documento MongoDB)

```java
@Document(collection = "productos")
@Data
@Builder
public class ProductoDocument {
    @Id
    private String id;           // UUID como string
    private String codigo;
    private String nombre;
    private String descripcion;
    private String categoriaId;
    private String categoriaNombre;
    private BigDecimal stockMinimo;
    private BigDecimal stockMaximo;
    private String estado;
    private Instant createdAt;
    private Instant updatedAt;
}
```

### Consumidor de Proyección (Kafka → MongoDB)

```java
@Component
@RequiredArgsConstructor
@Slf4j
public class ProductoProjectionConsumer {

    private final ReactiveKafkaConsumerTemplate<String, String> kafkaTemplate;
    private final ProductoMongoAdapter mongoAdapter;
    private final ObjectMapper objectMapper;
    private final CategoriaRepository categoriaRepository;

    @PostConstruct
    public void startConsuming() {
        kafkaTemplate.receive()
            .doOnNext(record -> log.debug("Received: topic={} offset={}",
                record.topic(), record.offset()))
            .flatMap(record -> processRecord(record)
                .doOnError(e -> log.error("Error procesando mensaje: {}", e.getMessage()))
                .onErrorResume(e -> Mono.empty())
                .doFinally(s -> record.receiverOffset().acknowledge())
            )
            .subscribe();
    }

    private Mono<Void> processRecord(ReceiverRecord<String, String> record) {
        return Mono.fromCallable(() -> objectMapper.readTree(record.value()))
            .flatMap(payload -> {
                String eventType = payload.get("eventType").asText();
                return switch (eventType) {
                    case "ProductoCreado" -> handleProductoCreado(payload);
                    case "ProductoActualizado" -> handleProductoActualizado(payload);
                    case "ProductoInactivado" -> handleProductoInactivado(payload);
                    default -> {
                        log.warn("Evento desconocido: {}", eventType);
                        yield Mono.empty();
                    }
                };
            });
    }

    private Mono<Void> handleProductoCreado(JsonNode payload) {
        UUID categoriaId = UUID.fromString(payload.get("categoriaId").asText());
        return categoriaRepository.findById(new CategoriaId(categoriaId))
            .map(cat -> ProductoDocument.builder()
                .id(payload.get("productoId").asText())
                .codigo(payload.get("codigo").asText())
                .nombre(payload.get("nombre").asText())
                .categoriaId(categoriaId.toString())
                .categoriaNombre(cat.getNombre())
                .stockMinimo(new BigDecimal(payload.get("stockMinimo").asText()))
                .stockMaximo(new BigDecimal(payload.get("stockMaximo").asText()))
                .estado("ACTIVO")
                .createdAt(Instant.parse(payload.get("occurredAt").asText()))
                .updatedAt(Instant.now())
                .build()
            )
            .flatMap(doc -> mongoAdapter.save(doc));
    }

    private Mono<Void> handleProductoActualizado(JsonNode payload) {
        return mongoAdapter.save(ProductoDocument.builder()
            .id(payload.get("productoId").asText())
            .nombre(payload.get("nombre").asText())
            .stockMinimo(new BigDecimal(payload.get("stockMinimo").asText()))
            .stockMaximo(new BigDecimal(payload.get("stockMaximo").asText()))
            .updatedAt(Instant.parse(payload.get("occurredAt").asText()))
            .build()
        );
    }

    private Mono<Void> handleProductoInactivado(JsonNode payload) {
        UUID productoId = UUID.fromString(payload.get("productoId").asText());
        return mongoAdapter.updateEstado(productoId, "INACTIVO");
    }
}
```

### Spring Security (idéntico a iam-service)

```java
@Configuration
@EnableWebFluxSecurity
public class SecurityConfig {

    @Bean
    public SecurityWebFilterChain securityWebFilterChain(ServerHttpSecurity http) {
        return http
            .csrf(csrf -> csrf.disable())
            .authorizeExchange(exchanges -> exchanges
                .pathMatchers("/actuator/health/**", "/actuator/prometheus").permitAll()
                .anyExchange().authenticated()
            )
            .oauth2ResourceServer(oauth2 -> oauth2
                .jwt(jwt -> jwt.jwkSetUri(
                    "${spring.security.oauth2.resourceserver.jwt.jwk-set-uri}"))
            )
            .build();
    }
}
```

### Configuración `application.yml`

```yaml
spring:
  application:
    name: catalog-service
  r2dbc:
    url: r2dbc:postgresql://${DB_HOST:localhost}:${DB_PORT:5432}/${DB_NAME:controlstock_catalog}
    username: ${DB_USER:controlstock_catalog}
    password: ${DB_PASSWORD:}
  data:
    mongodb:
      uri: mongodb://${MONGO_HOST:localhost}:${MONGO_PORT:27017}/${MONGO_DB:controlstock_readmodel}
  kafka:
    bootstrap-servers: ${KAFKA_BOOTSTRAP:localhost:9092}
    producer:
      key-serializer: org.apache.kafka.common.serialization.StringSerializer
      value-serializer: org.apache.kafka.common.serialization.StringSerializer
    consumer:
      group-id: catalog-projection-group
      auto-offset-reset: earliest
      key-deserializer: org.apache.kafka.common.serialization.StringDeserializer
      value-deserializer: org.apache.kafka.common.serialization.StringDeserializer
  security:
    oauth2:
      resourceserver:
        jwt:
          jwk-set-uri: ${KEYCLOAK_JWK_URI:http://localhost:8180/realms/controlstock/protocol/openid-connect/certs}

management:
  endpoints:
    web:
      exposure:
        include: health,prometheus
  endpoint:
    health:
      probes:
        enabled: true
```

---

## API REST

### Tabla de endpoints

| Método | Path | Descripción | Body Request | Response | Paginación |
|--------|------|-------------|-------------|---------|-----------|
| `GET` | `/catalog/categories` | Listar categorías | — | `200 Page<CategoriaDTO>` | `?page=0&size=20` |
| `POST` | `/catalog/categories` | Crear categoría | `CrearCategoriaRequest` | `201 CategoriaDTO` | — |
| `GET` | `/catalog/categories/{id}` | Obtener categoría | — | `200 CategoriaDTO` | — |
| `PUT` | `/catalog/categories/{id}` | Actualizar categoría | `ActualizarCategoriaRequest` | `200 CategoriaDTO` | — |
| `GET` | `/catalog/products` | Listar productos | — | `200 Page<ProductoDTO>` | `?page=0&size=20&categoriaId=&estado=` |
| `POST` | `/catalog/products` | Crear producto | `CrearProductoRequest` | `201 ProductoDTO` | — |
| `GET` | `/catalog/products/{id}` | Obtener producto | — | `200 ProductoDTO` | — |
| `PUT` | `/catalog/products/{id}` | Actualizar producto | `ActualizarProductoRequest` | `200 ProductoDTO` | — |
| `DELETE` | `/catalog/products/{id}` | Desactivar producto | — | `204 No Content` | — |

### Implementación con `@RestController` (WebFlux)

```java
@RestController
@RequestMapping("/catalog")
@RequiredArgsConstructor
public class CatalogController {

    private final CrearCategoriaUseCase crearCategoriaUseCase;
    private final ActualizarCategoriaUseCase actualizarCategoriaUseCase;
    private final DesactivarCategoriaUseCase desactivarCategoriaUseCase;
    private final ListarCategoriasUseCase listarCategoriasUseCase;
    private final ObtenerCategoriaUseCase obtenerCategoriaUseCase;

    private final CrearProductoUseCase crearProductoUseCase;
    private final ActualizarProductoUseCase actualizarProductoUseCase;
    private final InactivarProductoUseCase inactivarProductoUseCase;
    private final ListarProductosUseCase listarProductosUseCase;
    private final ObtenerProductoUseCase obtenerProductoUseCase;

    // ── Categorías ──────────────────────────────────────────

    @GetMapping("/categories")
    public Flux<CategoriaDTO> listarCategorias(
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "20") int size) {
        return listarCategoriasUseCase.ejecutar(PageRequest.of(page, size));
    }

    @PostMapping("/categories")
    @ResponseStatus(HttpStatus.CREATED)
    public Mono<CategoriaDTO> crearCategoria(
            @Valid @RequestBody CrearCategoriaRequest request) {
        return crearCategoriaUseCase.ejecutar(CrearCategoriaCommand.from(request));
    }

    @GetMapping("/categories/{id}")
    public Mono<CategoriaDTO> obtenerCategoria(@PathVariable UUID id) {
        return obtenerCategoriaUseCase.ejecutar(new CategoriaId(id));
    }

    @PutMapping("/categories/{id}")
    public Mono<CategoriaDTO> actualizarCategoria(
            @PathVariable UUID id,
            @Valid @RequestBody ActualizarCategoriaRequest request) {
        return actualizarCategoriaUseCase.ejecutar(new CategoriaId(id),
            ActualizarCategoriaCommand.from(request));
    }

    // ── Productos ──────────────────────────────────────────

    @GetMapping("/products")
    public Flux<ProductoDTO> listarProductos(
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "20") int size,
            @RequestParam Optional<UUID> categoriaId,
            @RequestParam Optional<String> estado) {
        ProductoFilter filter = new ProductoFilter(categoriaId, estado);
        return listarProductosUseCase.ejecutar(filter, PageRequest.of(page, size));
    }

    @PostMapping("/products")
    @ResponseStatus(HttpStatus.CREATED)
    public Mono<ProductoDTO> crearProducto(@Valid @RequestBody CrearProductoRequest request) {
        return crearProductoUseCase.ejecutar(CrearProductoCommand.from(request));
    }

    @GetMapping("/products/{id}")
    public Mono<ProductoDTO> obtenerProducto(@PathVariable UUID id) {
        return obtenerProductoUseCase.ejecutar(new ProductoId(id));
    }

    @PutMapping("/products/{id}")
    public Mono<ProductoDTO> actualizarProducto(
            @PathVariable UUID id,
            @Valid @RequestBody ActualizarProductoRequest request) {
        return actualizarProductoUseCase.ejecutar(
            new ProductoId(id), ActualizarProductoCommand.from(request));
    }

    @DeleteMapping("/products/{id}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public Mono<Void> inactivarProducto(@PathVariable UUID id) {
        return inactivarProductoUseCase.ejecutar(new ProductoId(id));
    }
}
```

### Manejo de errores

```java
@RestControllerAdvice
public class CatalogExceptionHandler {

    @ExceptionHandler(StockMaximoMenorOIgualMinimoException.class)
    @ResponseStatus(HttpStatus.UNPROCESSABLE_ENTITY)
    public Mono<ErrorResponse> handleStockInvalido(StockMaximoMenorOIgualMinimoException ex) {
        return Mono.just(new ErrorResponse("STOCK_INVALIDO",
            "stock_maximo debe ser mayor que stock_minimo"));
    }

    @ExceptionHandler(CodigoProductoDuplicadoException.class)
    @ResponseStatus(HttpStatus.CONFLICT)
    public Mono<ErrorResponse> handleCodigoDuplicado(CodigoProductoDuplicadoException ex) {
        return Mono.just(new ErrorResponse("CODIGO_DUPLICADO", ex.getMessage()));
    }

    @ExceptionHandler(CategoriaConProductosActivosException.class)
    @ResponseStatus(HttpStatus.UNPROCESSABLE_ENTITY)
    public Mono<ErrorResponse> handleCategoriaConActivos(CategoriaConProductosActivosException ex) {
        return Mono.just(new ErrorResponse("CATEGORIA_CON_PRODUCTOS_ACTIVOS", ex.getMessage()));
    }

    @ExceptionHandler(ProductoNoEncontradoException.class)
    @ResponseStatus(HttpStatus.NOT_FOUND)
    public Mono<ErrorResponse> handleProductoNoEncontrado(ProductoNoEncontradoException ex) {
        return Mono.just(new ErrorResponse("PRODUCTO_NO_ENCONTRADO", ex.getMessage()));
    }

    @ExceptionHandler(CategoriaNoEncontradaException.class)
    @ResponseStatus(HttpStatus.NOT_FOUND)
    public Mono<ErrorResponse> handleCategoriaNoEncontrada(CategoriaNoEncontradaException ex) {
        return Mono.just(new ErrorResponse("CATEGORIA_NO_ENCONTRADA", ex.getMessage()));
    }
}
```

---

## Especificación TDD por Capa (Red-Green-Refactor)

### Umbrales de cobertura requeridos

| Capa | Cobertura mínima | Nota |
|------|-----------------|------|
| Dominio | ≥ 90% | Énfasis especial en invariante `stock_minimo < stock_maximo` |
| Aplicación | ≥ 85% | |
| Infraestructura | ≥ 80% | Incluye relay outbox y proyección MongoDB |
| API REST | ≥ 80% | |

### Capa de Dominio — Tests

| Clase de Test | Método de Test | Invariante/Regla | Qué precede |
|--------------|---------------|-----------------|------------|
| `ProductoTest` | `crear_stockMinimoMenorQueMaximo_debeCrearCorrectamente` | Invariante central: flujo feliz | Implementación de `Producto.crear()` |
| `ProductoTest` | `crear_stockMaximoIgualAMinimo_debeLanzarExcepcion` | `stock_maximo == stock_minimo` → inválido | Excepción `StockMaximoMenorOIgualMinimoException` |
| `ProductoTest` | `crear_stockMaximoMenorQueMinimo_debeLanzarExcepcion` | `stock_maximo < stock_minimo` → inválido | Excepción `StockMaximoMenorOIgualMinimoException` |
| `ProductoTest` | `crear_stockMinimoNegativo_debeLanzarExcepcion` | `stock_minimo < 0` → inválido | Excepción `StockMinimoNegativoException` |
| `ProductoTest` | `crear_stockMinimoCero_debeCrearCorrectamente` | `stock_minimo = 0` es válido | `BigDecimal.ZERO` permitido en StockMinimo |
| `ProductoTest` | `actualizar_stockValidoNuevo_debeActualizarYRetornarEvento` | Actualización con invariante nueva válida | Implementación de `actualizar()` |
| `ProductoTest` | `actualizar_stockMaximoNuevoMenorQueMinimo_debeLanzarExcepcion` | Invariante se verifica en actualización también | Reutilización de `validarStock()` |
| `ProductoTest` | `actualizar_debeRetornarProductoActualizadoEvent` | Actualización genera evento de dominio | Implementación de `DomainEvent` en `actualizar()` |
| `ProductoTest` | `inactivar_productoActivo_debeSetearEstadoYRetornarEvento` | Inactivación genera evento | Implementación de `inactivar()` |
| `ProductoTest` | `inactivar_productoYaInactivo_debeLanzarExcepcion` | No inactivar dos veces | Excepción `ProductoYaInactivoException` |
| `CategoriaTest` | `desactivar_categoriaActiva_debeSetearInactivo` | Flujo feliz | Implementación de `desactivar()` |
| `CategoriaTest` | `desactivar_categoriaYaInactiva_debeLanzarExcepcion` | No desactivar dos veces | Excepción `CategoriaYaInactivaException` |
| `StockMinimoTest` | `stockMinimo_valorNegativo_debeLanzarExcepcion` | VO valida restricción | Implementación del VO |
| `StockMinimoTest` | `stockMinimo_cero_debeCrearCorrectamente` | Zero es válido para mínimo | Implementación del VO |
| `StockMaximoTest` | `stockMaximo_cero_debeLanzarExcepcion` | VO valida que > 0 | Implementación del VO |
| `CodigoProductoTest` | `codigo_vacio_debeLanzarExcepcion` | Código no vacío | Implementación del VO |
| `CodigoProductoTest` | `codigo_superiorA50Chars_debeLanzarExcepcion` | Longitud máxima 50 | Implementación del VO |
| `ProductoCreadoTest` | `evento_debeTenerTopicCorrecto` | Topic Kafka correcto | Implementación de evento |

### Capa de Aplicación — Tests

| Clase de Test | Método de Test | Invariante/Regla | Qué precede |
|--------------|---------------|-----------------|------------|
| `CrearProductoUseCaseTest` | `ejecutar_todosLosDatosValidos_debeGuardarYRegistrarOutbox` | Flujo feliz: BD + outbox | Implementación de `CrearProductoUseCase` |
| `CrearProductoUseCaseTest` | `ejecutar_codigoDuplicado_debeLanzarExcepcion` | Unicidad de código | Excepción `CodigoProductoDuplicadoException` |
| `CrearProductoUseCaseTest` | `ejecutar_categoriaNoExiste_debeLanzarExcepcion` | Categoría debe existir | Excepción `CategoriaNoEncontradaException` |
| `CrearProductoUseCaseTest` | `ejecutar_stockInvalido_debeLanzarExcepcionDeDominio` | Invariante verificada en dominio | Propagación de `StockMaximoMenorOIgualMinimoException` |
| `ActualizarProductoUseCaseTest` | `ejecutar_productoExistente_debeActualizarYRegistrarOutbox` | Flujo feliz | Implementación de `ActualizarProductoUseCase` |
| `ActualizarProductoUseCaseTest` | `ejecutar_nuevoStockInvalido_debeLanzarExcepcion` | Invariante verificada en update | Propagación desde dominio |
| `ActualizarProductoUseCaseTest` | `ejecutar_productoNoExistente_debeLanzarExcepcion` | ID no encontrado | Excepción `ProductoNoEncontradoException` |
| `InactivarProductoUseCaseTest` | `ejecutar_productoActivo_debeInactivarYRegistrarOutbox` | Flujo feliz | Implementación de `InactivarProductoUseCase` |
| `InactivarProductoUseCaseTest` | `ejecutar_productoYaInactivo_debeLanzarExcepcion` | Dominio impide doble inactivación | Propagación de excepción |
| `CrearCategoriaUseCaseTest` | `ejecutar_codigoNuevo_debeCrearCategoria` | Flujo feliz | Implementación de `CrearCategoriaUseCase` |
| `CrearCategoriaUseCaseTest` | `ejecutar_codigoDuplicado_debeLanzarExcepcion` | Unicidad de código categoría | Excepción `CodigoCategoriaDuplicadoException` |
| `DesactivarCategoriaUseCaseTest` | `ejecutar_sinProductosActivos_debeDesactivar` | Flujo feliz | Implementación de `DesactivarCategoriaUseCase` |
| `DesactivarCategoriaUseCaseTest` | `ejecutar_conProductosActivos_debeLanzarExcepcion` | Regla de negocio: integridad referencial | Excepción `CategoriaConProductosActivosException` |

### Capa de Infraestructura — Tests (Testcontainers)

#### Tests de adaptadores R2DBC con PostgreSQL

```java
@Testcontainers
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.NONE)
class ProductoR2dbcAdapterTest {

    @Container
    static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:16")
        .withDatabaseName("test_catalog")
        .withInitScript("db/migration/V1__init_catalog.sql");

    @Autowired
    private ProductoR2dbcAdapter adapter;

    @Test
    void save_productoNuevo_debeGuardarYRetornar() {
        Producto producto = crearProductoFake();
        StepVerifier.create(adapter.save(producto))
            .assertNext(saved -> {
                assertThat(saved.getCodigo()).isEqualTo(producto.getCodigo());
                assertThat(saved.getStockMinimo()).isEqualTo(producto.getStockMinimo());
            })
            .verifyComplete();
    }
}
```

| Clase de Test | Método de Test | Invariante/Regla | Qué precede |
|--------------|---------------|-----------------|------------|
| `ProductoR2dbcAdapterTest` | `save_productoNuevo_debeGuardarConStockCorrecto` | NUMERIC(12,3) persiste con precisión | Implementación del adaptador |
| `ProductoR2dbcAdapterTest` | `save_productoExistente_debeActualizarPorUpsert` | ON CONFLICT UPDATE funciona | Lógica de upsert |
| `ProductoR2dbcAdapterTest` | `findAll_conFiltroCategoria_debeRetornarSoloDeEsaCategoria` | Filtro por categoría funciona | Implementación dinámica de query |
| `ProductoR2dbcAdapterTest` | `findAll_conFiltroEstado_debeRetornarSoloCorrecto` | Filtro por estado funciona | Implementación dinámica de query |
| `ProductoR2dbcAdapterTest` | `existsByCodigo_codigoExistente_debeRetornarTrue` | Verificación de unicidad | Implementación de `existsByCodigo` |
| `CategoriaR2dbcAdapterTest` | `save_categoriaNueva_debeGuardarYRetornar` | INSERT correcto | Implementación del adaptador |
| `CategoriaR2dbcAdapterTest` | `tieneProductosActivos_conProductoActivo_debeRetornarTrue` | Verificación de productos activos | Implementación de `tieneProductosActivos` |
| `CategoriaR2dbcAdapterTest` | `tieneProductosActivos_sinProductos_debeRetornarFalse` | Categoría sin productos puede desactivarse | Verificación del query |
| `OutboxR2dbcAdapterTest` | `save_evento_debeGuardarConStatusPending` | Outbox entry creada como PENDING | Implementación de `save` outbox |
| `OutboxR2dbcAdapterTest` | `findPending_debeRetornarSoloPending` | Solo se leen entradas PENDING | Query con `WHERE status = 'PENDING'` |
| `OutboxR2dbcAdapterTest` | `markAsPublished_debeActualizarStatusYPublishedAt` | Transición PENDING → PUBLISHED | Implementación de `markAsPublished` |
| `OutboxR2dbcAdapterTest` | `markAsFailed_debeActualizarStatus` | Transición PENDING → FAILED | Implementación de `markAsFailed` |
| `OutboxRelayTest` | `relay_conEntradaPending_debePublicarYMarcarPublished` | Relay completo: outbox → Kafka → PUBLISHED | Implementación de `OutboxRelay` con Kafka mock |
| `OutboxRelayTest` | `relay_kafkaFalla_debeMarcarFailed` | Resiliencia: error de Kafka → FAILED | Manejo de errores en relay |

#### Tests de proyección MongoDB con Testcontainers

```java
@Testcontainers
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.NONE)
class ProductoMongoAdapterTest {

    @Container
    static MongoDBContainer mongodb = new MongoDBContainer("mongo:7");

    @DynamicPropertySource
    static void mongoProps(DynamicPropertyRegistry registry) {
        registry.add("spring.data.mongodb.uri", mongodb::getReplicaSetUrl);
    }

    @Autowired
    private ProductoMongoAdapter adapter;
    @Autowired
    private ReactiveMongoTemplate mongoTemplate;

    @Test
    void save_documentoNuevo_debeGuardarEnColeccion() {
        ProductoDocument doc = buildDocFake();
        StepVerifier.create(adapter.save(doc)
            .then(mongoTemplate.findById(doc.getId(), ProductoDocument.class, "productos"))
        )
        .assertNext(found -> {
            assertThat(found.getCodigo()).isEqualTo(doc.getCodigo());
            assertThat(found.getEstado()).isEqualTo("ACTIVO");
        })
        .verifyComplete();
    }
}
```

| Clase de Test | Método de Test | Invariante/Regla | Qué precede |
|--------------|---------------|-----------------|------------|
| `ProductoMongoAdapterTest` | `save_documentoNuevo_debeGuardarEnColeccion` | Inserción en MongoDB correcta | Implementación del adaptador |
| `ProductoMongoAdapterTest` | `save_documentoExistente_debeActualizar` | Upsert por `_id` funciona | Comportamiento de `mongoTemplate.save` |
| `ProductoMongoAdapterTest` | `updateEstado_debeActualizarSoloElCampoEstado` | Actualización parcial funciona | Implementación de `Update.update()` |
| `ProductoProjectionConsumerTest` | `handleProductoCreado_debeGuardarDocumentoEnMongoDB` | Evento Creado → documento MongoDB | Implementación del consumer |
| `ProductoProjectionConsumerTest` | `handleProductoActualizado_debeActualizarDocumento` | Evento Actualizado → update MongoDB | Implementación del consumer |
| `ProductoProjectionConsumerTest` | `handleProductoInactivado_debeActualizarEstadoAInactivo` | Evento Inactivado → estado INACTIVO | Implementación del consumer |

### Capa API REST — Tests (@WebFluxTest)

| Clase de Test | Método de Test | Invariante/Regla | Qué precede |
|--------------|---------------|-----------------|------------|
| `CatalogControllerTest` | `crearProducto_requestValido_debeRetornar201` | Endpoint POST /catalog/products funciona | Implementación del controlador |
| `CatalogControllerTest` | `crearProducto_codigoDuplicado_debeRetornar409` | Error 409 mapeado | `@ExceptionHandler` CodigoDuplicado |
| `CatalogControllerTest` | `crearProducto_stockInvalido_debeRetornar422` | Error 422 mapeado para invariante | `@ExceptionHandler` StockInvalido |
| `CatalogControllerTest` | `crearProducto_requestInvalido_debeRetornar400` | @Valid funciona | `@ExceptionHandler` WebExchangeBindException |
| `CatalogControllerTest` | `listarProductos_debeRetornar200ConFlux` | GET /catalog/products funciona | Implementación de `listarProductos` |
| `CatalogControllerTest` | `listarProductos_conFiltros_pasaFiltrosAlUseCase` | Parámetros de query mapeados | Integración controller→use case |
| `CatalogControllerTest` | `obtenerProducto_idExistente_debeRetornar200` | GET /catalog/products/{id} funciona | Implementación de `obtenerProducto` |
| `CatalogControllerTest` | `obtenerProducto_idNoExistente_debeRetornar404` | Error 404 mapeado | `@ExceptionHandler` ProductoNoEncontrado |
| `CatalogControllerTest` | `actualizarProducto_stockValido_debeRetornar200` | PUT funciona con stock válido | Implementación de `actualizarProducto` |
| `CatalogControllerTest` | `actualizarProducto_stockInvalido_debeRetornar422` | Invariante propagada desde dominio | Error 422 en PUT |
| `CatalogControllerTest` | `inactivarProducto_exitoso_debeRetornar204` | DELETE retorna 204 | Implementación de `inactivarProducto` |
| `CatalogControllerTest` | `inactivarProducto_yaInactivo_debeRetornar422` | Error 422 para producto ya inactivo | `@ExceptionHandler` ProductoYaInactivo |
| `CatalogControllerTest` | `crearCategoria_requestValido_debeRetornar201` | POST /catalog/categories funciona | Implementación del controlador |
| `CatalogControllerTest` | `listarCategorias_debeRetornar200ConFlux` | GET /catalog/categories funciona | Implementación de `listarCategorias` |
| `CatalogControllerTest` | `desactivarCategoria_conProductosActivos_debeRetornar422` | Regla de negocio mapeada | `@ExceptionHandler` CategoriaConActivos |
| `SecurityTest` | `endpoint_sinToken_debeRetornar401` | JWT obligatorio | Configuración Spring Security |
| `SecurityTest` | `actuatorHealth_sinToken_debeRetornar200` | Actuator público | Exclusión en SecurityConfig |

---

## Criterios de Aceptación

### Dominio — Invariante Central

| # | Criterio | Verificación |
|---|----------|-------------|
| 1 | `Producto.crear()` con `stock_maximo <= stock_minimo` lanza `StockMaximoMenorOIgualMinimoException` | Tests `ProductoTest` RED → GREEN → REFACTOR |
| 2 | `Producto.actualizar()` verifica la misma invariante | Test `actualizar_stockMaximoNuevoMenorQueMinimo` GREEN |
| 3 | `stock_minimo = 0` es válido (producto sin stock mínimo configurado) | Test `crear_stockMinimoCero` GREEN |
| 4 | `StockMinimo < 0` lanza excepción desde el VO | Test `StockMinimoTest` GREEN |
| 5 | `Categoria.desactivar()` lanza excepción si ya inactiva | Test `CategoriaTest` GREEN |
| 6 | Cobertura de dominio ≥ 90% | Reporte JaCoCo en Jenkins |

### TDD por capa

| # | Criterio | Verificación |
|---|----------|-------------|
| 7 | Todos los tests de dominio escritos ANTES de la implementación | Historial de commits muestra test primero |
| 8 | Tests de aplicación usan mocks de puertos sin Spring context | No hay `@SpringBootTest` en tests de aplicación |
| 9 | Tests de R2DBC usan Testcontainers con PostgreSQL 16 real | `@Container PostgreSQLContainer` visible |
| 10 | Tests de MongoDB usan Testcontainers con MongoDB 7 real | `@Container MongoDBContainer` visible |
| 11 | Relay outbox verificado con `StepVerifier` (Testcontainers) | Test `OutboxRelayTest` GREEN |
| 12 | Proyección MongoDB verificada con `StepVerifier` | Test `ProductoProjectionConsumerTest` GREEN |
| 13 | Cobertura aplicación ≥ 85% | Reporte JaCoCo en Jenkins |
| 14 | Cobertura infraestructura ≥ 80% | Reporte JaCoCo en Jenkins |
| 15 | Cobertura API REST ≥ 80% | Reporte JaCoCo en Jenkins |

### Funcionalidad del Outbox + Kafka

| # | Criterio | Verificación |
|---|----------|-------------|
| 16 | Al crear un producto, se inserta una fila en `outbox` con `status='PENDING'` | Verificado en test Testcontainers |
| 17 | El `OutboxRelay` publica el evento a Kafka y marca `status='PUBLISHED'` | Test `OutboxRelayTest` GREEN |
| 18 | Si Kafka falla, el relay marca `status='FAILED'` y no detiene el servicio | Test de error en `OutboxRelayTest` GREEN |
| 19 | Tres topics creados en Kafka: `producto-creado`, `producto-actualizado`, `producto-inactivado` | `kafka-topics.sh --list` muestra los 3 topics |

### Proyección MongoDB

| # | Criterio | Verificación |
|---|----------|-------------|
| 20 | Al recibir `ProductoCreado`, se crea documento en colección `productos` | Test `handleProductoCreado` GREEN |
| 21 | Al recibir `ProductoActualizado`, se actualiza el documento | Test `handleProductoActualizado` GREEN |
| 22 | Al recibir `ProductoInactivado`, el documento pasa a `estado: INACTIVO` | Test `handleProductoInactivado` GREEN |
| 23 | El consumer usa `acknowledgeMode` manual para evitar pérdida de mensajes | Configuración del consumer verificada |

### API REST

| # | Criterio | Verificación |
|---|----------|-------------|
| 24 | Los 9 endpoints de la API están implementados y retornan HTTP correctos | Tabla de endpoints cubierta al 100% |
| 25 | `PUT /catalog/products/{id}` retorna 422 si `stock_maximo <= stock_minimo` | Test `actualizarProducto_stockInvalido` GREEN |
| 26 | `DELETE /catalog/products/{id}` retorna 204 al desactivar exitosamente | Test GREEN |
| 27 | Todos los endpoints protegidos retornan 401 sin token JWT | Test `SecurityTest` GREEN |
| 28 | `GET /catalog/products` acepta filtros por `categoriaId` y `estado` | Test `listarProductos_conFiltros` GREEN |

### Pipeline CI/CD y despliegue

| # | Criterio | Verificación |
|---|----------|-------------|
| 29 | Pipeline Jenkins completa todas las etapas para `catalog-service` | BlueOcean muestra todas las etapas en verde |
| 30 | Imagen `catalog-service:<tag>` publicada en Gitea registry | Push exitoso verificado en stage Build |
| 31 | ArgoCD despliega `catalog-service` en namespace `apps` | `kubectl get pod -n apps -l app=catalog-service` Running |
| 32 | `GET /actuator/health/readiness` retorna 200 en K3s | Smoke test del pipeline GREEN |
| 33 | `GET /actuator/prometheus` expone métricas | Stage `Smoke Tests` GREEN |
| 34 | SonarQube Quality Gate pasa para `catalog-service` | Stage `Quality Gates` verde en Jenkins |
