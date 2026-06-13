# Etapa 3f — Microservicio: Supplier Service (BC-06)

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

El **Supplier Service** (Bounded Context BC-06) es el microservicio responsable de la gestión del ciclo de vida de proveedores y sus configuraciones de integración en ControlStock. Es el **sexto microservicio en implementarse**. Mantiene el catálogo de proveedores y las referencias de configuración a HashiCorp Vault, garantizando que las credenciales de integración nunca se almacenen en texto plano en la base de datos.

### Responsabilidades del servicio

| Responsabilidad | Descripción |
|----------------|-------------|
| **Registro de proveedores** | Crear proveedores con identificación fiscal única, método de integración y estado ACTIVO |
| **Modificación de proveedores** | Actualizar datos de proveedor y configuración de integración |
| **Desactivación de proveedores** | Transición de estado a INACTIVO (no eliminación física) |
| **Gestión de configuración de integración** | Almacenar protocolo, endpoint y ruta Vault por proveedor — nunca credenciales en texto plano |
| **Publicación de eventos de dominio** | Publicar `ProveedorCreado` y `ProveedorActualizado` mediante Transactional Outbox → Kafka |
| **Proyección de lectura** | Consumir sus propios eventos y mantener la colección `proveedores` en MongoDB `controlstock_readmodel` |
| **Referencia a Vault** | `integration_configs.vault_secret_path` apunta al path de Vault donde viven las credenciales; el servicio nunca expone esas credenciales |

### Lo que el servicio NO hace

| Restricción | Justificación |
|-------------|---------------|
| No elimina físicamente proveedores | La desactivación es la única transición terminal; las referencias históricas de movimientos deben permanecer consistentes |
| No verifica movimientos asociados directamente | No hay acceso cross-BD; la lógica de negocio que impide desvincular un proveedor con movimientos es responsabilidad del orquestador o del llamador de nivel superior |
| No participa en sagas | No hay flujos distribuidos que involucren supplier-service como participante |
| No tiene dependencias REST de otros servicios de dominio | Solo depende de Keycloak para validación de token |
| No almacena credenciales de integración | Las credenciales viven en HashiCorp Vault; solo se almacena la ruta (`vault_secret_path`) |
| No tiene proyección a MongoDB propia por write-side | Solo consume sus propios eventos para mantener la colección de lectura |

### Bounded Context BC-06

```
┌──────────────────────────────────────────────────────────────────────┐
│                    Supplier Service (BC-06)                          │
│                                                                      │
│  ┌──────────────────────┐    ┌────────────────────────────────────┐  │
│  │      suppliers       │    │       integration_configs          │  │
│  │  - nombre            │◄───│  - protocolo (REST/FTP/SFTP)       │  │
│  │  - identificacion    │    │  - endpoint                        │  │
│  │    _fiscal (UNIQUE)  │    │  - vault_secret_path (REQUIRED)    │  │
│  │  - metodo_integracion│    │  - configuracion_extra (JSONB)     │  │
│  │  - estado (ACTIVO/   │    └────────────────────────────────────┘  │
│  │    INACTIVO)         │                                            │
│  └─────────────┬────────┘                                            │
│                │                                                     │
│                ▼                                                     │
│        ┌──────────────────────┐                                      │
│        │   outbox (PG)        │                                      │
│        │   PENDING/PUBLISHED  │                                      │
│        └──────────┬───────────┘                                      │
│                   │                                                  │
│          Outbox Relay (Scheduler R2DBC)                              │
└──────────────────────────────────────────────────────────────────────┘
         │ (produce via outbox)              │ (consume)
         ▼                                   ▼
┌──────────────────────────────┐   ┌─────────────────────────────────┐
│  Apache Kafka                │   │  MongoDB Projection Consumer    │
│  controlstock.supplier       │◄──│  (BC-06)                        │
│  .proveedor-creado           │   │  → colección `proveedores`      │
│  .proveedor-actualizado      │   │    en controlstock_readmodel    │
└──────────────────────────────┘   └─────────────────────────────────┘

                    ┌────────────────────────────────────┐
                    │  HashiCorp Vault (KV v2)           │
                    │  path: controlstock/<env>/         │
                    │    integration-service/            │
                    │    proveedor-{supplier_id}         │
                    │  (solo vault_secret_path guardado  │
                    │   en DB; credenciales en Vault)    │
                    └────────────────────────────────────┘
```

### Base de datos

- **PostgreSQL 16** — schema `controlstock_supplier` (suppliers, integration_configs, outbox)
- **MongoDB 7** — base de datos `controlstock_readmodel`, colección `proveedores` (lectura)
- **Tecnología de acceso**: Spring Data R2DBC (PostgreSQL reactivo) + Reactive MongoDB Driver

### Nota sobre el outbox en BC-06

El esquema original del diseño técnico no incluía tabla `outbox` en BC-06. Sin embargo, dado que el servicio es un productor Kafka (eventos `ProveedorCreado` y `ProveedorActualizado`), se requiere la tabla `outbox` para garantizar consistencia eventual mediante el patrón Transactional Outbox. Esta tabla **se incluye en el changelog de Liquibase** de este microservicio como parte del paso de implementación, junto con `suppliers` e `integration_configs`.

---

## Prerrequisitos

| Prerrequisito | Documento de referencia | Verificación |
|--------------|------------------------|-------------|
| Etapa 0 — Infraestructura base completa | `DEV-ControlStock-00-infrastructure.md` | K3s corriendo, namespaces activos |
| Etapa 0c — Observabilidad configurada | `DEV-ControlStock-0c-observability.md` | Prometheus + Grafana activos |
| Etapa 1 — Bases de datos aprovisionadas | `DEV-ControlStock-01-databases.md` | PostgreSQL schema `controlstock_supplier` + MongoDB `controlstock_readmodel` |
| Etapa 2 — Scaffold generado | `DEV-ControlStock-02-scaffold.md` | Proyecto Maven `supplier-service` generado |
| Etapa 2b — Pipeline CI/CD configurado | `DEV-ControlStock-02b-cicd.md` | Job `supplier-service` activo en Jenkins |
| **Etapa 3a — IAM Service corriendo** | `DEV-ControlStock-03-ms-iam-service.md` | Keycloak emitiendo tokens JWT con roles para realm `controlstock` |
| Kafka (Strimzi KRaft) corriendo | Etapa 0 | Topics `controlstock.supplier.*` creados |
| HashiCorp Vault KV v2 activo | Etapa 0 | Path `controlstock/<env>/integration-service/` accesible |

### Verificación de prerrequisitos

```bash
# Verificar schema PostgreSQL supplier (después de aplicar Liquibase)
kubectl exec -n databases deploy/postgresql -- psql \
  -U controlstock_supplier -d controlstock_supplier \
  -c "\dt" | grep -E "suppliers|integration_configs|outbox"

# Verificar MongoDB colección proveedores
kubectl exec -n databases deploy/mongodb -- mongosh \
  --eval "use controlstock_readmodel; db.getCollectionNames()" \
  | grep "proveedores"

# Verificar topics Kafka supplier
kubectl exec -n kafka deploy/kafka -- \
  kafka-topics.sh --list --bootstrap-server kafka:9092 \
  | grep "controlstock.supplier"
# Salida esperada:
# controlstock.supplier.proveedor-actualizado
# controlstock.supplier.proveedor-creado

# Verificar Vault path accesible
kubectl exec -n vault deploy/vault -- vault kv list \
  controlstock/dev/integration-service/ 2>/dev/null || echo "path vacío — OK"

# Verificar token JWT con roles correctos
TOKEN=$(curl -s -X POST \
  "http://<VPS_IP>:8180/realms/controlstock/protocol/openid-connect/token" \
  -d "client_id=test-client&grant_type=password&username=admin@test.com&password=test" \
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
| **I-1** | Dominio | Entidad `Supplier`; VOs `IdentificacionFiscal`, `NombreProveedor`, `SupplierId`; invariante unicidad e identificación no vacía | Tests dominio GREEN |
| **I-2** | Dominio | Entidad `IntegrationConfig`; VO `VaultSecretPath`; invariante path no vacío y formato correcto | Tests VaultSecretPath GREEN |
| **I-3** | Dominio | Eventos de dominio: `ProveedorCreado`, `ProveedorActualizado`; transición `desactivar()` | Tests transiciones GREEN |
| **I-4** | Dominio | Puertos: `SupplierRepository`, `IntegrationConfigRepository`, `OutboxRepository`, `ProveedoresProjectionRepository` | Interfaces definidas; compilación GREEN |
| **I-5** | Aplicación | `RegistrarProveedorUseCase`, `ActualizarProveedorUseCase` | Tests aplicación con mocks GREEN |
| **I-6** | Aplicación | `DesactivarProveedorUseCase`, `ConsultarProveedoresUseCase` | Tests idempotencia desactivación GREEN |
| **I-7** | Infraestructura | R2DBC adapters para `suppliers`, `integration_configs`, `outbox`; Liquibase changelog con tabla `outbox` | Tests Testcontainers (PostgreSQL) GREEN |
| **I-8** | Infraestructura | `OutboxRelay` (scheduler R2DBC → Kafka) | Tests Testcontainers (PostgreSQL + Kafka) GREEN |
| **I-9** | Infraestructura | MongoDB projection consumer (`ProveedorCreado` / `ProveedorActualizado` → colección `proveedores`) | Tests Testcontainers (MongoDB + Kafka) GREEN |
| **I-10** | API REST | Endpoints completos + `@ExceptionHandler` (400, 403, 404, 409) | Tests `@WebFluxTest` GREEN |
| **I-11** | Integración | Tests E2E en K3s: flujo POST supplier → evento Kafka → proyección MongoDB | Suite de humo GREEN |

---

## Capa de Dominio

### Entidades

#### `Supplier`

```java
// src/main/java/com/controlstock/supplier/domain/model/Supplier.java
public class Supplier {
    private final SupplierId id;
    private NombreProveedor nombre;
    private final IdentificacionFiscal identificacionFiscal;  // UNIQUE, inmutable
    private final MetodoIntegracion metodoIntegracion;        // REST | ARCHIVO, inmutable
    private EstadoProveedor estado;
    private final Instant createdAt;
    private Instant updatedAt;

    public static Supplier crear(
            NombreProveedor nombre,
            IdentificacionFiscal identificacionFiscal,
            MetodoIntegracion metodoIntegracion) {
        return new Supplier(
            new SupplierId(UUID.randomUUID()),
            nombre, identificacionFiscal, metodoIntegracion,
            EstadoProveedor.ACTIVO,
            Instant.now(), Instant.now()
        );
    }

    /**
     * Actualiza datos del proveedor.
     * La identificación fiscal y el método de integración son inmutables.
     */
    public List<DomainEvent> actualizar(NombreProveedor nuevoNombre) {
        this.nombre = Objects.requireNonNull(nuevoNombre);
        this.updatedAt = Instant.now();
        return List.of(new ProveedorActualizado(this));
    }

    /**
     * Desactiva el proveedor. Idempotente si ya está INACTIVO.
     * Invariante: no se puede reactivar un proveedor desde este método.
     */
    public List<DomainEvent> desactivar() {
        if (this.estado == EstadoProveedor.INACTIVO) {
            return Collections.emptyList(); // ya inactivo — idempotente
        }
        this.estado = EstadoProveedor.INACTIVO;
        this.updatedAt = Instant.now();
        return List.of(new ProveedorActualizado(this));
    }

    public boolean isActivo() { return EstadoProveedor.ACTIVO == this.estado; }
    // Getters...
}
```

#### `IntegrationConfig`

La invariante central de este bounded context para la configuración es que `vault_secret_path` es **siempre obligatorio** y debe seguir el formato `controlstock/<env>/integration-service/proveedor-{supplier_id}`. Las credenciales NUNCA se almacenan en esta entidad.

```java
// src/main/java/com/controlstock/supplier/domain/model/IntegrationConfig.java
public class IntegrationConfig {
    private final IntegrationConfigId id;
    private final SupplierId supplierId;
    private Protocolo protocolo;            // REST | FTP | SFTP
    private Endpoint endpoint;              // nullable
    private VaultSecretPath vaultSecretPath; // REQUIRED, nunca vacío
    private Map<String, Object> configuracionExtra; // JSONB, nullable

    private final Instant createdAt;
    private Instant updatedAt;

    public static IntegrationConfig crear(
            SupplierId supplierId,
            Protocolo protocolo,
            Endpoint endpoint,
            VaultSecretPath vaultSecretPath,
            Map<String, Object> configuracionExtra) {
        Objects.requireNonNull(vaultSecretPath, "vault_secret_path es obligatorio");
        return new IntegrationConfig(
            new IntegrationConfigId(UUID.randomUUID()),
            supplierId, protocolo, endpoint, vaultSecretPath,
            configuracionExtra, Instant.now(), Instant.now()
        );
    }

    /**
     * Actualiza la configuración de integración.
     * El vault_secret_path NO puede actualizarse a null o vacío.
     */
    public void actualizar(
            Protocolo nuevoProtocolo,
            Endpoint nuevoEndpoint,
            VaultSecretPath nuevoVaultPath,
            Map<String, Object> nuevaConfigExtra) {
        Objects.requireNonNull(nuevoVaultPath, "vault_secret_path no puede ser nulo al actualizar");
        this.protocolo = nuevoProtocolo;
        this.endpoint = nuevoEndpoint;
        this.vaultSecretPath = nuevoVaultPath;
        this.configuracionExtra = nuevaConfigExtra;
        this.updatedAt = Instant.now();
    }
    // Getters...
}
```

### Value Objects

| Value Object | Validaciones | Clase |
|-------------|-------------|-------|
| `SupplierId` | UUID no nulo | `com.controlstock.supplier.domain.vo.SupplierId` |
| `IntegrationConfigId` | UUID no nulo | `com.controlstock.supplier.domain.vo.IntegrationConfigId` |
| `NombreProveedor` | No nulo, no vacío, máx 200 chars | `com.controlstock.supplier.domain.vo.NombreProveedor` |
| `IdentificacionFiscal` | No nulo, no vacío, máx 50 chars, solo alfanumérico+guiones | `com.controlstock.supplier.domain.vo.IdentificacionFiscal` |
| `MetodoIntegracion` | Enum: `REST`, `ARCHIVO` | `com.controlstock.supplier.domain.vo.MetodoIntegracion` |
| `Protocolo` | Enum: `REST`, `FTP`, `SFTP` | `com.controlstock.supplier.domain.vo.Protocolo` |
| `Endpoint` | Nullable; si presente, URL válida máx 500 chars | `com.controlstock.supplier.domain.vo.Endpoint` |
| `VaultSecretPath` | No nulo, no vacío, formato `controlstock/<env>/integration-service/proveedor-<uuid>` | `com.controlstock.supplier.domain.vo.VaultSecretPath` |

```java
// VaultSecretPath — el más crítico: referencia Vault, nunca credenciales reales
public record VaultSecretPath(String value) {
    private static final Pattern PATH_PATTERN =
        Pattern.compile("^controlstock/[a-z]+/integration-service/proveedor-[0-9a-f\\-]{36}$");

    public VaultSecretPath {
        Objects.requireNonNull(value, "vault_secret_path no puede ser nulo");
        if (value.isBlank()) {
            throw new VaultSecretPathVacioException();
        }
        if (!PATH_PATTERN.matcher(value).matches()) {
            throw new VaultSecretPathFormatoInvalidoException(value);
        }
    }

    /**
     * Factory: genera el path estándar para un proveedor dado el entorno.
     */
    public static VaultSecretPath forSupplier(String env, UUID supplierId) {
        return new VaultSecretPath(
            "controlstock/" + env + "/integration-service/proveedor-" + supplierId
        );
    }
}

// IdentificacionFiscal — clave de negocio única
public record IdentificacionFiscal(String value) {
    private static final Pattern FISCAL_PATTERN = Pattern.compile("^[A-Za-z0-9\\-]{1,50}$");

    public IdentificacionFiscal {
        Objects.requireNonNull(value, "identificacion_fiscal no puede ser nula");
        if (value.isBlank()) {
            throw new IdentificacionFiscalVaciaException();
        }
        if (!FISCAL_PATTERN.matcher(value).matches()) {
            throw new IdentificacionFiscalFormatoInvalidoException(value);
        }
    }
}

// NombreProveedor
public record NombreProveedor(String value) {
    public NombreProveedor {
        Objects.requireNonNull(value, "nombre del proveedor no puede ser nulo");
        if (value.isBlank()) {
            throw new NombreProveedorVacioException();
        }
        if (value.length() > 200) {
            throw new NombreProveedorDemasiadoLargoException(value.length());
        }
    }
}
```

### Excepciones de Dominio

```java
// VaultSecretPath vacío
public class VaultSecretPathVacioException extends RuntimeException {
    public VaultSecretPathVacioException() {
        super("vault_secret_path es obligatorio y no puede estar vacío");
    }
}

// VaultSecretPath formato inválido
public class VaultSecretPathFormatoInvalidoException extends RuntimeException {
    public VaultSecretPathFormatoInvalidoException(String path) {
        super(String.format(
            "vault_secret_path '%s' no sigue el formato esperado: " +
            "controlstock/<env>/integration-service/proveedor-<uuid>", path));
    }
}

// Identificación fiscal duplicada (lanzada en use case al verificar unicidad)
public class IdentificacionFiscalDuplicadaException extends RuntimeException {
    private final String identificacionFiscal;
    public IdentificacionFiscalDuplicadaException(String fiscal) {
        super(String.format("Ya existe un proveedor con identificación fiscal '%s'", fiscal));
        this.identificacionFiscal = fiscal;
    }
}

// Proveedor no encontrado
public class ProveedorNoEncontradoException extends RuntimeException {
    private final UUID supplierId;
    public ProveedorNoEncontradoException(SupplierId id) {
        super(String.format("Proveedor no encontrado: %s", id.value()));
        this.supplierId = id.value();
    }
}
```

### Eventos de Dominio

```java
// Interfaz base
public interface DomainEvent {
    String getEventType();
    String getAggregateType();
    UUID getAggregateId();
    Instant getOccurredAt();
    String getTopic();
}

// ProveedorCreado — publicado al registrar un nuevo proveedor
public record ProveedorCreado(
    UUID proveedorId,
    String nombre,
    String identificacionFiscal,
    String metodoIntegracion,
    String estado,
    Instant occurredAt
) implements DomainEvent {
    public ProveedorCreado(Supplier supplier) {
        this(supplier.getId().value(),
             supplier.getNombre().value(),
             supplier.getIdentificacionFiscal().value(),
             supplier.getMetodoIntegracion().name(),
             supplier.getEstado().name(),
             Instant.now());
    }

    @Override public String getEventType()     { return "ProveedorCreado"; }
    @Override public String getAggregateType() { return "Supplier"; }
    @Override public UUID getAggregateId()     { return proveedorId; }
    @Override public Instant getOccurredAt()   { return occurredAt; }
    @Override public String getTopic() {
        return "controlstock.supplier.proveedor-creado";
    }
}

// ProveedorActualizado — publicado al actualizar o desactivar un proveedor
public record ProveedorActualizado(
    UUID proveedorId,
    String nombre,
    String identificacionFiscal,
    String metodoIntegracion,
    String estado,
    Instant occurredAt
) implements DomainEvent {
    public ProveedorActualizado(Supplier supplier) {
        this(supplier.getId().value(),
             supplier.getNombre().value(),
             supplier.getIdentificacionFiscal().value(),
             supplier.getMetodoIntegracion().name(),
             supplier.getEstado().name(),
             Instant.now());
    }

    @Override public String getEventType()     { return "ProveedorActualizado"; }
    @Override public String getAggregateType() { return "Supplier"; }
    @Override public UUID getAggregateId()     { return proveedorId; }
    @Override public Instant getOccurredAt()   { return occurredAt; }
    @Override public String getTopic() {
        return "controlstock.supplier.proveedor-actualizado";
    }
}
```

### Topics de Kafka

| Evento | Topic | Partitions | Retention | Consumido por |
|--------|-------|-----------|-----------|---------------|
| `ProveedorCreado` | `controlstock.supplier.proveedor-creado` | 3 | 7 días | `audit-service`, projection consumer (BC-06) |
| `ProveedorActualizado` | `controlstock.supplier.proveedor-actualizado` | 3 | 7 días | `audit-service`, projection consumer (BC-06) |

### Puertos (Interfaces de Dominio)

```java
// Puerto: SupplierRepository (PostgreSQL, R2DBC)
public interface SupplierRepository {
    Mono<Supplier> save(Supplier supplier);
    Mono<Supplier> findById(SupplierId id);
    Mono<Supplier> findByIdentificacionFiscal(IdentificacionFiscal fiscal);
    Flux<Supplier> findAll(SupplierFilter filter, Pageable pageable);
    Mono<Boolean> existsByIdentificacionFiscal(IdentificacionFiscal fiscal);
}

// Puerto: IntegrationConfigRepository (PostgreSQL, R2DBC)
public interface IntegrationConfigRepository {
    Mono<IntegrationConfig> save(IntegrationConfig config);
    Mono<IntegrationConfig> findBySupplierId(SupplierId supplierId);
    Mono<Void> deleteBySupplierId(SupplierId supplierId);
}

// Puerto: OutboxRepository (PostgreSQL, R2DBC)
public interface OutboxRepository {
    Mono<Void> save(DomainEvent event);
    Flux<OutboxEntry> findPending(int limit);
    Mono<Void> markAsPublished(UUID outboxId);
    Mono<Void> markAsFailed(UUID outboxId);
}

// Puerto: ProveedoresProjectionRepository (MongoDB reactivo)
public interface ProveedoresProjectionRepository {
    Mono<Void> upsert(ProveedorDocument document);
    Mono<ProveedorDocument> findByProveedorId(UUID proveedorId);
}

// Puerto: EventPublisherPort (Kafka)
public interface EventPublisherPort {
    Mono<Void> publish(String topic, String key, String payload);
}
```

### Invariantes de Dominio

| Invariante | Regla | Excepción |
|-----------|-------|-----------|
| **Identificación fiscal única** | `identificacion_fiscal` único en el sistema (verificado en use case) | `IdentificacionFiscalDuplicadaException` |
| **Vault path obligatorio** | `vault_secret_path` no puede ser nulo ni vacío al crear/actualizar `IntegrationConfig` | `VaultSecretPathVacioException` |
| **Vault path formato correcto** | Debe seguir `controlstock/<env>/integration-service/proveedor-<uuid>` | `VaultSecretPathFormatoInvalidoException` |
| **Sin credenciales en DB** | `integration_configs` NO contiene contraseñas, tokens ni claves — solo la ruta Vault | Regla de diseño (revisión de código) |
| **Desactivación idempotente** | Desactivar un proveedor ya INACTIVO no lanza excepción; retorna lista de eventos vacía | Comportamiento de dominio |
| **Nombre no vacío** | `nombre` obligatorio, máx 200 chars | `NombreProveedorVacioException` |

---

## Capa de Aplicación

### Use Cases

#### `RegistrarProveedorUseCase`

```java
@Service
@RequiredArgsConstructor
public class RegistrarProveedorUseCase {
    private final SupplierRepository supplierRepository;
    private final IntegrationConfigRepository integrationConfigRepository;
    private final OutboxRepository outboxRepository;
    private final TransactionalOperator transactionalOperator;

    /**
     * Registra un nuevo proveedor con su configuración de integración.
     * Verifica unicidad de identificación fiscal.
     * Publica ProveedorCreado via Outbox dentro de la misma transacción R2DBC.
     * NOTA: vault_secret_path se genera automáticamente siguiendo la convención
     *       controlstock/<env>/integration-service/proveedor-{supplierId}
     *       El caller proporciona los demás campos de integración.
     */
    public Mono<SupplierResponse> ejecutar(RegistrarProveedorCommand cmd) {
        return supplierRepository.existsByIdentificacionFiscal(cmd.identificacionFiscal())
            .flatMap(exists -> {
                if (Boolean.TRUE.equals(exists)) {
                    return Mono.error(new IdentificacionFiscalDuplicadaException(
                        cmd.identificacionFiscal().value()));
                }
                Supplier supplier = Supplier.crear(
                    cmd.nombre(), cmd.identificacionFiscal(), cmd.metodoIntegracion()
                );
                VaultSecretPath vaultPath = VaultSecretPath.forSupplier(
                    cmd.env(), supplier.getId().value()
                );
                IntegrationConfig config = IntegrationConfig.crear(
                    supplier.getId(), cmd.protocolo(), cmd.endpoint(),
                    vaultPath, cmd.configuracionExtra()
                );
                DomainEvent evento = new ProveedorCreado(supplier);

                return supplierRepository.save(supplier)
                    .then(integrationConfigRepository.save(config))
                    .then(outboxRepository.save(evento))
                    .thenReturn(SupplierResponse.from(supplier, config));
            })
            .as(transactionalOperator::transactional);
    }
}
```

#### `ActualizarProveedorUseCase`

```java
@Service
@RequiredArgsConstructor
public class ActualizarProveedorUseCase {
    private final SupplierRepository supplierRepository;
    private final IntegrationConfigRepository integrationConfigRepository;
    private final OutboxRepository outboxRepository;
    private final TransactionalOperator transactionalOperator;

    /**
     * Actualiza datos del proveedor y/o su configuración de integración.
     * Solo proveedores ACTIVOS pueden actualizarse.
     * Publica ProveedorActualizado via Outbox.
     */
    public Mono<SupplierResponse> ejecutar(ActualizarProveedorCommand cmd) {
        return supplierRepository.findById(cmd.supplierId())
            .switchIfEmpty(Mono.error(new ProveedorNoEncontradoException(cmd.supplierId())))
            .flatMap(supplier -> {
                if (!supplier.isActivo()) {
                    return Mono.error(new ProveedorInactivoException(cmd.supplierId()));
                }
                List<DomainEvent> eventos = supplier.actualizar(cmd.nombre());

                return supplierRepository.save(supplier)
                    .then(integrationConfigRepository.findBySupplierId(supplier.getId())
                        .flatMap(config -> {
                            config.actualizar(
                                cmd.protocolo(), cmd.endpoint(),
                                cmd.vaultSecretPath(), cmd.configuracionExtra()
                            );
                            return integrationConfigRepository.save(config);
                        })
                    )
                    .then(Flux.fromIterable(eventos)
                        .flatMap(outboxRepository::save)
                        .then())
                    .then(integrationConfigRepository.findBySupplierId(supplier.getId())
                        .map(config -> SupplierResponse.from(supplier, config)));
            })
            .as(transactionalOperator::transactional);
    }
}
```

#### `DesactivarProveedorUseCase`

```java
@Service
@RequiredArgsConstructor
public class DesactivarProveedorUseCase {
    private final SupplierRepository supplierRepository;
    private final OutboxRepository outboxRepository;
    private final TransactionalOperator transactionalOperator;

    /**
     * Desactiva un proveedor (estado INACTIVO).
     * Idempotente: si ya está INACTIVO, no publica evento duplicado.
     * No elimina fisicamente ni su IntegrationConfig.
     */
    public Mono<SupplierResponse> ejecutar(SupplierId supplierId) {
        return supplierRepository.findById(supplierId)
            .switchIfEmpty(Mono.error(new ProveedorNoEncontradoException(supplierId)))
            .flatMap(supplier -> {
                List<DomainEvent> eventos = supplier.desactivar();
                return supplierRepository.save(supplier)
                    .then(Flux.fromIterable(eventos)
                        .flatMap(outboxRepository::save)
                        .then())
                    .thenReturn(SupplierResponse.fromSupplierOnly(supplier));
            })
            .as(transactionalOperator::transactional);
    }
}
```

#### `ConsultarProveedoresUseCase`

```java
@Service
@RequiredArgsConstructor
public class ConsultarProveedoresUseCase {
    private final SupplierRepository supplierRepository;
    private final IntegrationConfigRepository integrationConfigRepository;

    public Flux<SupplierResponse> listar(SupplierFilter filter, Pageable pageable) {
        return supplierRepository.findAll(filter, pageable)
            .flatMap(supplier ->
                integrationConfigRepository.findBySupplierId(supplier.getId())
                    .map(config -> SupplierResponse.from(supplier, config))
                    .defaultIfEmpty(SupplierResponse.fromSupplierOnly(supplier))
            );
    }

    public Mono<SupplierResponse> obtener(SupplierId supplierId) {
        return supplierRepository.findById(supplierId)
            .switchIfEmpty(Mono.error(new ProveedorNoEncontradoException(supplierId)))
            .flatMap(supplier ->
                integrationConfigRepository.findBySupplierId(supplier.getId())
                    .map(config -> SupplierResponse.from(supplier, config))
                    .defaultIfEmpty(SupplierResponse.fromSupplierOnly(supplier))
            );
    }
}
```

### DTOs

```java
// Command: RegistrarProveedorCommand
public record RegistrarProveedorCommand(
    NombreProveedor nombre,
    IdentificacionFiscal identificacionFiscal,
    MetodoIntegracion metodoIntegracion,
    Protocolo protocolo,
    Endpoint endpoint,           // nullable
    Map<String, Object> configuracionExtra, // nullable
    String env                   // "dev" | "staging" | "prod"
) {}

// Command: ActualizarProveedorCommand
public record ActualizarProveedorCommand(
    SupplierId supplierId,
    NombreProveedor nombre,
    Protocolo protocolo,
    Endpoint endpoint,
    VaultSecretPath vaultSecretPath,
    Map<String, Object> configuracionExtra
) {}

// Response: SupplierResponse
public record SupplierResponse(
    UUID id,
    String nombre,
    String identificacionFiscal,
    String metodoIntegracion,
    String estado,
    IntegrationConfigResponse integrationConfig,
    Instant createdAt,
    Instant updatedAt
) {
    public static SupplierResponse from(Supplier supplier, IntegrationConfig config) { /* ... */ }
    public static SupplierResponse fromSupplierOnly(Supplier supplier) { /* ... */ }
}

// Response: IntegrationConfigResponse — NUNCA expone credenciales; solo vaultSecretPath
public record IntegrationConfigResponse(
    UUID id,
    String protocolo,
    String endpoint,
    String vaultSecretPath,      // path de referencia; las credenciales están en Vault
    Instant updatedAt
) {}
```

---

## Capa de Infraestructura

### Liquibase Changelog — BC-06 (con Outbox)

```sql
-- changelog/V1__bc06_supplier_schema.sql
-- Tabla suppliers
CREATE TABLE suppliers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    nombre VARCHAR(200) NOT NULL,
    identificacion_fiscal VARCHAR(50) NOT NULL UNIQUE,
    metodo_integracion VARCHAR(20) NOT NULL CHECK (metodo_integracion IN ('REST','ARCHIVO')),
    estado VARCHAR(20) NOT NULL DEFAULT 'ACTIVO' CHECK (estado IN ('ACTIVO','INACTIVO')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Tabla integration_configs
CREATE TABLE integration_configs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    supplier_id UUID NOT NULL UNIQUE REFERENCES suppliers(id),
    protocolo VARCHAR(20) NOT NULL CHECK (protocolo IN ('REST','FTP','SFTP')),
    endpoint VARCHAR(500),
    vault_secret_path VARCHAR(300) NOT NULL,  -- REQUIRED: nunca vacío
    configuracion_extra JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Tabla outbox (ADICIONAL al esquema original del diseño técnico)
-- Necesaria para patrón Transactional Outbox: garantiza que ProveedorCreado
-- y ProveedorActualizado se publiquen a Kafka sin dual-write.
CREATE TABLE outbox (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    aggregate_type VARCHAR(100) NOT NULL,
    aggregate_id UUID NOT NULL,
    event_type VARCHAR(100) NOT NULL,
    topic VARCHAR(200) NOT NULL,
    payload JSONB NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING','PUBLISHED','FAILED')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    published_at TIMESTAMPTZ
);
CREATE INDEX idx_outbox_status_created ON outbox(status, created_at)
    WHERE status = 'PENDING';
```

### R2DBC — `SupplierR2dbcAdapter`

```java
@Repository
@RequiredArgsConstructor
public class SupplierR2dbcAdapter implements SupplierRepository {
    private final SupplierR2dbcRepo r2dbcRepo;

    @Override
    public Mono<Supplier> save(Supplier supplier) {
        return r2dbcRepo.save(SupplierMapper.toEntity(supplier))
            .map(SupplierMapper::toDomain);
    }

    @Override
    public Mono<Supplier> findById(SupplierId id) {
        return r2dbcRepo.findById(id.value())
            .map(SupplierMapper::toDomain);
    }

    @Override
    public Mono<Supplier> findByIdentificacionFiscal(IdentificacionFiscal fiscal) {
        return r2dbcRepo.findByIdentificacionFiscal(fiscal.value())
            .map(SupplierMapper::toDomain);
    }

    @Override
    public Flux<Supplier> findAll(SupplierFilter filter, Pageable pageable) {
        return r2dbcRepo.findByFilter(
            filter.estado() != null ? filter.estado().name() : null,
            pageable
        ).map(SupplierMapper::toDomain);
    }

    @Override
    public Mono<Boolean> existsByIdentificacionFiscal(IdentificacionFiscal fiscal) {
        return r2dbcRepo.existsByIdentificacionFiscal(fiscal.value());
    }
}

// Spring Data R2DBC entity
@Table("suppliers")
public class SupplierEntity {
    @Id private UUID id;
    private String nombre;
    private String identificacionFiscal;
    private String metodoIntegracion;
    private String estado;
    private Instant createdAt;
    private Instant updatedAt;
}
```

### R2DBC — `IntegrationConfigR2dbcAdapter`

```java
@Repository
@RequiredArgsConstructor
public class IntegrationConfigR2dbcAdapter implements IntegrationConfigRepository {
    private final IntegrationConfigR2dbcRepo r2dbcRepo;

    @Override
    public Mono<IntegrationConfig> save(IntegrationConfig config) {
        return r2dbcRepo.save(IntegrationConfigMapper.toEntity(config))
            .map(IntegrationConfigMapper::toDomain);
    }

    @Override
    public Mono<IntegrationConfig> findBySupplierId(SupplierId supplierId) {
        return r2dbcRepo.findBySupplierId(supplierId.value())
            .map(IntegrationConfigMapper::toDomain);
    }
}

// Spring Data R2DBC entity
@Table("integration_configs")
public class IntegrationConfigEntity {
    @Id private UUID id;
    private UUID supplierId;
    private String protocolo;
    private String endpoint;
    private String vaultSecretPath;   // NUNCA nulo en DB
    @Column("configuracion_extra")
    private String configuracionExtraJson; // serializado como JSONB
    private Instant createdAt;
    private Instant updatedAt;
}
```

### R2DBC — `OutboxRelay`

```java
@Component
@RequiredArgsConstructor
@Slf4j
public class OutboxRelay {
    private final OutboxR2dbcRepo outboxRepo;
    private final EventPublisherPort eventPublisher;
    private final TransactionalOperator tx;

    @Scheduled(fixedDelay = 500)
    public void relay() {
        outboxRepo.findPendingLimit(50)
            .flatMap(entry ->
                eventPublisher.publish(entry.getTopic(), entry.getAggregateId().toString(),
                                       entry.getPayload())
                    .then(outboxRepo.markAsPublished(entry.getId()))
                    .onErrorResume(e -> {
                        log.error("OutboxRelay fallo publicando entry={}", entry.getId(), e);
                        return outboxRepo.markAsFailed(entry.getId());
                    })
            )
            .as(tx::transactional)
            .subscribe();
    }
}
```

### Kafka — Productor

```java
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

### Kafka — Projection Consumer (MongoDB)

```java
@Component
@RequiredArgsConstructor
@Slf4j
public class ProveedorProjectionConsumer {
    private final ReactiveKafkaConsumerTemplate<String, String> consumerTemplate;
    private final ProveedoresProjectionRepository projectionRepository;
    private final ObjectMapper objectMapper;

    /**
     * Consume ProveedorCreado y ProveedorActualizado para actualizar
     * la colección `proveedores` en MongoDB.
     * Consumer group: controlstock-supplier-projection
     */
    @PostConstruct
    public void startConsumer() {
        consumerTemplate.receiveAutoAck()
            .flatMap(record -> {
                String topic = record.topic();
                try {
                    if (topic.endsWith("proveedor-creado") ||
                        topic.endsWith("proveedor-actualizado")) {
                        ProveedorEventPayload payload =
                            objectMapper.readValue(record.value(), ProveedorEventPayload.class);
                        ProveedorDocument doc = ProveedorDocument.from(payload);
                        return projectionRepository.upsert(doc);
                    }
                    return Mono.empty();
                } catch (Exception e) {
                    log.error("Error procesando evento supplier topic={}", topic, e);
                    return Mono.empty();
                }
            })
            .subscribe();
    }
}

// MongoDB document para colección `proveedores`
@Document(collection = "proveedores")
public class ProveedorDocument {
    @Id
    private String proveedorId;
    private String nombre;
    private String identificacionFiscal;
    private String metodoIntegracion;
    private String estado;
    private long totalMovimientos;  // incrementado por ETL/jobs externos
    private Instant updatedAt;

    public static ProveedorDocument from(ProveedorEventPayload payload) { /* ... */ }
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
                .pathMatchers(HttpMethod.GET, "/suppliers", "/suppliers/**")
                    .authenticated()
                .pathMatchers(HttpMethod.POST, "/suppliers")
                    .hasAnyRole("ADMIN", "SUPERVISOR")
                .pathMatchers(HttpMethod.PUT, "/suppliers/**")
                    .hasAnyRole("ADMIN", "SUPERVISOR")
                .pathMatchers(HttpMethod.DELETE, "/suppliers/**")
                    .hasRole("ADMIN")
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
| `GET` | `/suppliers` | Listar proveedores (filtro: `estado`, paginado) | Autenticado | 200 |
| `POST` | `/suppliers` | Registrar nuevo proveedor con configuración de integración | ADMIN, SUPERVISOR | 201 |
| `GET` | `/suppliers/{id}` | Detalle de un proveedor con su config de integración | Autenticado | 200 |
| `PUT` | `/suppliers/{id}` | Actualizar datos y/o configuración de integración | ADMIN, SUPERVISOR | 200 |
| `DELETE` | `/suppliers/{id}` | Desactivar proveedor (estado INACTIVO) | ADMIN | 200 |

### Contratos de Request/Response

```json
// POST /suppliers — registrar proveedor
// Request
{
  "nombre": "Distribuidora XYZ S.A.",
  "identificacionFiscal": "30-71234567-8",
  "metodoIntegracion": "REST",
  "protocolo": "REST",
  "endpoint": "https://api.distribuidora-xyz.com/v1/ordenes",
  "configuracionExtra": {
    "timeout_ms": 5000,
    "retry_attempts": 3
  }
}
// Response 201
{
  "id": "uuid",
  "nombre": "Distribuidora XYZ S.A.",
  "identificacionFiscal": "30-71234567-8",
  "metodoIntegracion": "REST",
  "estado": "ACTIVO",
  "integrationConfig": {
    "id": "uuid",
    "protocolo": "REST",
    "endpoint": "https://api.distribuidora-xyz.com/v1/ordenes",
    "vaultSecretPath": "controlstock/dev/integration-service/proveedor-<uuid>",
    "updatedAt": "2025-01-15T10:00:00Z"
  },
  "createdAt": "2025-01-15T10:00:00Z",
  "updatedAt": "2025-01-15T10:00:00Z"
}

// POST /suppliers — identificación fiscal duplicada
// Response 409 Conflict
{
  "error": "IDENTIFICACION_FISCAL_DUPLICADA",
  "mensaje": "Ya existe un proveedor con identificación fiscal '30-71234567-8'",
  "identificacionFiscal": "30-71234567-8"
}

// POST /suppliers — vault_secret_path vacío (si se pasa manualmente)
// Response 400
{
  "error": "VAULT_SECRET_PATH_VACIO",
  "mensaje": "vault_secret_path es obligatorio y no puede estar vacío"
}

// DELETE /suppliers/{id} — desactivar
// Response 200
{
  "id": "uuid",
  "estado": "INACTIVO",
  "updatedAt": "2025-01-15T11:00:00Z"
}

// GET /suppliers/{id} — proveedor no encontrado
// Response 404
{
  "error": "PROVEEDOR_NO_ENCONTRADO",
  "mensaje": "Proveedor no encontrado: <uuid>"
}
```

### `@ExceptionHandler` en `GlobalExceptionHandler`

| Excepción | HTTP Status | Campo en body |
|-----------|-------------|---------------|
| `ProveedorNoEncontradoException` | 404 | `supplierId` |
| `IdentificacionFiscalDuplicadaException` | 409 | `identificacionFiscal` |
| `VaultSecretPathVacioException` | 400 | `error: VAULT_SECRET_PATH_VACIO` |
| `VaultSecretPathFormatoInvalidoException` | 400 | `error: VAULT_SECRET_PATH_FORMATO_INVALIDO` |
| `NombreProveedorVacioException` | 400 | `error: NOMBRE_PROVEEDOR_VACIO` |
| `ProveedorInactivoException` | 409 | `supplierId`, `estado: INACTIVO` |
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
| D-01 | `SupplierTest` | `crear_conDatosValidos_estadoActivo` | `estado == ACTIVO`; `identificacionFiscal` preservada |
| D-02 | `SupplierTest` | `desactivar_proveedorActivo_cambiaEstadoYRetornaEvento` | `estado == INACTIVO`; lista contiene `ProveedorActualizado` |
| D-03 | `SupplierTest` | `desactivar_proveedorYaInactivo_retornaListaVacia` | `estado == INACTIVO` (sin cambio); lista vacía — idempotente |
| D-04 | `SupplierTest` | `actualizar_nuevoNombreValido_retornaProveedorActualizado` | `nombre` actualizado; lista contiene `ProveedorActualizado` |
| D-05 | `NombreProveedorTest` | `nombreVacio_lanzaExcepcion` | `NombreProveedorVacioException` |
| D-06 | `NombreProveedorTest` | `nombreSuperaLimite200_lanzaExcepcion` | `NombreProveedorDemasiadoLargoException` |
| D-07 | `IdentificacionFiscalTest` | `fiscalVacia_lanzaExcepcion` | `IdentificacionFiscalVaciaException` |
| D-08 | `IdentificacionFiscalTest` | `fiscalConCaracteresInvalidos_lanzaExcepcion` | `IdentificacionFiscalFormatoInvalidoException` |
| D-09 | `VaultSecretPathTest` | `pathVacio_lanzaExcepcion` | `VaultSecretPathVacioException` |
| D-10 | `VaultSecretPathTest` | `pathFormatoInvalido_lanzaExcepcion` | `VaultSecretPathFormatoInvalidoException` |
| D-11 | `VaultSecretPathTest` | `pathFormatoCorrecto_creaExitosamente` | No lanza excepción; `value` preservado |
| D-12 | `VaultSecretPathTest` | `forSupplier_generaPathCorrecto` | Path = `controlstock/dev/integration-service/proveedor-<uuid>` |
| D-13 | `IntegrationConfigTest` | `crear_conVaultPathNulo_lanzaExcepcion` | `NullPointerException` por `Objects.requireNonNull` |
| D-14 | `IntegrationConfigTest` | `actualizar_conVaultPathNulo_lanzaExcepcion` | `NullPointerException` |

**Cobertura objetivo: dominio >= 90%**

### Capa de Aplicación

| # | Test Class | Caso de prueba | Mock / Aserción |
|---|-----------|----------------|-----------------|
| A-01 | `RegistrarProveedorUseCaseTest` | `ejecutar_identificacionUnica_registraYPublicaEvento` | `supplierRepo.save(...)` llamado; `outboxRepo.save(ProveedorCreado)` llamado; `StepVerifier` verifica `SupplierResponse` |
| A-02 | `RegistrarProveedorUseCaseTest` | `ejecutar_identificacionDuplicada_lanzaExcepcion` | `expectError(IdentificacionFiscalDuplicadaException.class)`; repos de escritura NO llamados |
| A-03 | `ActualizarProveedorUseCaseTest` | `ejecutar_proveedorActivo_actualizaYPublicaEvento` | `outboxRepo.save(ProveedorActualizado)` llamado; `StepVerifier` verifica response |
| A-04 | `ActualizarProveedorUseCaseTest` | `ejecutar_proveedorNoExiste_lanzaExcepcion` | `expectError(ProveedorNoEncontradoException.class)` |
| A-05 | `ActualizarProveedorUseCaseTest` | `ejecutar_proveedorInactivo_lanzaExcepcion` | `expectError(ProveedorInactivoException.class)` |
| A-06 | `DesactivarProveedorUseCaseTest` | `ejecutar_proveedorActivo_desactivaYPublicaEvento` | `outboxRepo.save(ProveedorActualizado)` llamado; `estado == INACTIVO` |
| A-07 | `DesactivarProveedorUseCaseTest` | `ejecutar_proveedorYaInactivo_noPublicaDuplicado` | `outboxRepo.save(...)` NO llamado (lista de eventos vacía) |
| A-08 | `DesactivarProveedorUseCaseTest` | `ejecutar_proveedorNoExiste_lanzaExcepcion` | `expectError(ProveedorNoEncontradoException.class)` |

**Cobertura objetivo: aplicación >= 85%**

### Capa de Infraestructura

| # | Test Class | Tipo | Caso de prueba |
|---|-----------|------|----------------|
| I-01 | `SupplierR2dbcAdapterTest` | `@DataR2dbcTest` + Testcontainers PG | `save_findById_roundtrip_preservaDatosCompletos` |
| I-02 | `SupplierR2dbcAdapterTest` | `@DataR2dbcTest` + Testcontainers PG | `existsByIdentificacionFiscal_retornaTrue_cuandoExiste` |
| I-03 | `SupplierR2dbcAdapterTest` | `@DataR2dbcTest` + Testcontainers PG | `findAll_conFiltroEstadoActivo_retornaSoloActivos` |
| I-04 | `IntegrationConfigR2dbcAdapterTest` | `@DataR2dbcTest` + Testcontainers PG | `save_findBySupplierId_roundtrip_preservaVaultPath` |
| I-05 | `IntegrationConfigR2dbcAdapterTest` | `@DataR2dbcTest` + Testcontainers PG | `save_conVaultPathVacio_falla_aConstraintDB` |
| I-06 | `OutboxRelayIntegrationTest` | `@SpringBootTest` + Testcontainers PG + Kafka | `relay_publicaProveedorCreado_en_topicCorrecto` |
| I-07 | `ProveedorProjectionConsumerTest` | `@SpringBootTest` + Testcontainers Kafka + MongoDB | `consumer_recibeProveedorCreado_upsertEnMongoDB` |
| I-08 | `ProveedorProjectionConsumerTest` | `@SpringBootTest` + Testcontainers Kafka + MongoDB | `consumer_recibeProveedorActualizado_actualizaDocumento` |

**Cobertura objetivo: infraestructura >= 80%**

### API REST

| # | Test Class | Tipo | Caso de prueba |
|---|-----------|------|----------------|
| R-01 | `SupplierControllerTest` | `@WebFluxTest` | `POST /suppliers → 201 con estado ACTIVO y vaultSecretPath en response` |
| R-02 | `SupplierControllerTest` | `@WebFluxTest` | `POST /suppliers identificación fiscal duplicada → 409` |
| R-03 | `SupplierControllerTest` | `@WebFluxTest` | `POST /suppliers nombre vacío → 400` |
| R-04 | `SupplierControllerTest` | `@WebFluxTest` | `POST /suppliers con rol OPERADOR → 403` |
| R-05 | `SupplierControllerTest` | `@WebFluxTest` | `GET /suppliers/{id} existente → 200 con integrationConfig.vaultSecretPath visible` |
| R-06 | `SupplierControllerTest` | `@WebFluxTest` | `GET /suppliers/{id} no existe → 404` |
| R-07 | `SupplierControllerTest` | `@WebFluxTest` | `PUT /suppliers/{id} proveedor activo → 200` |
| R-08 | `SupplierControllerTest` | `@WebFluxTest` | `PUT /suppliers/{id} proveedor inactivo → 409` |
| R-09 | `SupplierControllerTest` | `@WebFluxTest` | `DELETE /suppliers/{id} con rol ADMIN → 200 con estado INACTIVO` |
| R-10 | `SupplierControllerTest` | `@WebFluxTest` | `DELETE /suppliers/{id} segunda llamada → 200 (idempotente)` |
| R-11 | `SupplierControllerTest` | `@WebFluxTest` | `GET /suppliers sin token → 401` |

### Configuración Testcontainers

```java
// src/test/java/com/controlstock/supplier/infrastructure/BaseIntegrationTest.java
@Testcontainers
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
public abstract class BaseIntegrationTest {

    @Container
    static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:16-alpine")
        .withDatabaseName("controlstock_supplier_test")
        .withInitScript("db/schema-supplier.sql");

    @Container
    static KafkaContainer kafka = new KafkaContainer(
        DockerImageName.parse("confluentinc/cp-kafka:7.6.0"));

    @Container
    static MongoDBContainer mongodb = new MongoDBContainer("mongo:7.0");

    @DynamicPropertySource
    static void configureProperties(DynamicPropertyRegistry registry) {
        registry.add("spring.r2dbc.url",
            () -> "r2dbc:postgresql://" + postgres.getHost() + ":" +
                  postgres.getFirstMappedPort() + "/controlstock_supplier_test");
        registry.add("spring.r2dbc.username", postgres::getUsername);
        registry.add("spring.r2dbc.password", postgres::getPassword);
        registry.add("spring.kafka.bootstrap-servers", kafka::getBootstrapServers);
        registry.add("spring.data.mongodb.uri", mongodb::getReplicaSetUrl);
    }
}
```

---

## Criterios de Aceptación

| # | Criterio | Verificación |
|---|---------|-------------|
| AC-01 | `POST /suppliers` con datos válidos devuelve 201; `vaultSecretPath` en response sigue el formato `controlstock/<env>/integration-service/proveedor-<uuid>` | Test R-01 + revisión de response |
| AC-02 | `POST /suppliers` con `identificacion_fiscal` duplicada devuelve **HTTP 409** con `error: IDENTIFICACION_FISCAL_DUPLICADA` | Test R-02, A-02 |
| AC-03 | `integration_configs.vault_secret_path` es **siempre NOT NULL** en la base de datos; intentar guardar con path vacío falla con constraint | Test I-05; constraint de DB verificado |
| AC-04 | La respuesta de la API **nunca expone credenciales**; solo expone `vaultSecretPath` (referencia a Vault) | Revisión de `IntegrationConfigResponse`: ausencia de campos `password`, `token`, `key` |
| AC-05 | `DELETE /suppliers/{id}` es **idempotente**: segunda llamada retorna 200 sin publicar evento duplicado en Kafka | Test R-10, D-03, A-07 |
| AC-06 | `ProveedorCreado` y `ProveedorActualizado` son publicados **exclusivamente via Outbox** — no hay dual-write directo | Revisión de código: `EventPublisherPort` solo inyectado en `OutboxRelay` |
| AC-07 | La colección `proveedores` en MongoDB se actualiza correctamente al recibir `ProveedorCreado` y `ProveedorActualizado` | Test I-07, I-08; verificación manual en K3s |
| AC-08 | `PUT /suppliers/{id}` sobre proveedor INACTIVO devuelve **HTTP 409** | Test R-08, A-05 |
| AC-09 | Cobertura: Dominio >= 90%, Aplicación >= 85%, Infraestructura >= 80% | JaCoCo en pipeline Jenkins |
| AC-10 | `GET /actuator/health/readiness` retorna `{ "status": "UP" }` con PostgreSQL, Kafka y MongoDB como health indicators | Verificación manual en K3s |
| AC-11 | Toda la cadena reactiva usa `StepVerifier`; ausencia de `block()` verificada con `BlockHound` | BlockHound activo en `@SpringBootTest` |
