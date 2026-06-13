# Etapa 3i — Microservicio: Integration Service (BC-09)

## ACL Centralizado + Orquestador de Sagas (Saga-01 y Saga-02)

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

El **Integration Service** (Bounded Context BC-09) es el microservicio más complejo de ControlStock. Es el **noveno microservicio en implementarse** y cumple dos funciones arquitectónicas fundamentales: actúa como **ACL (Anti-Corruption Layer) centralizado** que aisla a todos los servicios de dominio de las particularidades y modelos de los sistemas externos, y actúa como **orquestador de Sagas distribuidas** (Saga-01 y Saga-02) mediante Apache Camel Saga EIP con coordinación LRA a través de Narayana.

### Roles arquitectónicos

#### Rol 1 — ACL Centralizado

El integration-service es la **única puerta de entrada y salida** hacia sistemas externos. Ningún otro microservicio de ControlStock tiene dependencias de red con sistemas fuera del cluster K3s. Esta decisión arquitectónica (registrada en el ADC) garantiza que los cambios en contratos externos no se propaguen a los Bounded Contexts de dominio.

| Sistema externo | Protocolo | Componente Camel | Traducción de modelo |
|----------------|-----------|-----------------|---------------------|
| Servicio de Notificaciones (externo) | HTTP/REST | `camel-http` | `NotificacionRequest` (interno) → DTO externo |
| Proveedores REST | HTTP/REST | `camel-http` | `SolicitudReposicion` → DTO por proveedor (ACL por proveedor) |
| Proveedores FTP/SFTP | File transfer | `camel-file` / `camel-ftp` | `SolicitudReposicion` → archivo CSV/EDI por proveedor |

Todas las credenciales de acceso a sistemas externos se obtienen en tiempo de ejecución desde **Vault** mediante `spring-cloud-vault-config`. Nunca se almacenan en ConfigMaps ni variables de entorno en texto claro.

#### Rol 2 — Orquestador de Sagas

El integration-service coordina dos sagas distribuidas usando **Camel Saga EIP** con registro de participantes via **Narayana LRA (Long Running Actions)**:

- **Saga-01 — Reposición de Inventario**: orquestación end-to-end del flujo de reposición con proveedor externo.
- **Saga-02 — Ajuste con Aprobación**: monitoreo y coordinación del flujo de ajuste que involucra adjustment-service e inventory-service.

#### Rol 3 — API Pública ControlStock (RF-020)

Expone la API pública de ControlStock para consumidores externos (terceros, integraciones B2B) a través de Kong. Estos endpoints representan la fachada pública del sistema hacia el exterior.

### Responsabilidades del servicio

| Responsabilidad | Descripción |
|----------------|-------------|
| **ACL Notificaciones** | Recibir solicitudes de notificación desde alert-service, traducir modelo interno y despachar al servicio externo de notificaciones vía HTTP; gestionar reintentos con backoff exponencial |
| **ACL Proveedores REST** | Traducir `SolicitudReposicion` al modelo específico de cada proveedor y enviar por HTTP; registrar resultado en `integration_logs` |
| **ACL Proveedores FTP/SFTP** | Generar archivo (CSV/EDI) con la solicitud de reposición y subirlo al FTP/SFTP del proveedor; confirmar transferencia |
| **Orquestación Saga-01** | Iniciar y coordinar la saga de reposición: comunicar al proveedor → registrar entrada en inventory-service → notificar a alert-service; ejecutar compensaciones en orden inverso ante fallo |
| **Orquestación Saga-02** | Monitorear y coordinar la saga de ajuste: supervisar transiciones, activar compensaciones si inventory-service falla al aplicar el ajuste aprobado |
| **Persistencia de trazabilidad** | Registrar cada operación de integración en `integration_logs`; rastrear intentos de notificación en `notification_dispatch`; registrar estado de sagas en `saga_instance` y `saga_step_log` |
| **API pública ControlStock** | Exponer endpoints públicos para consumidores externos autenticados vía Kong + Keycloak |
| **Gestión de credenciales dinámicas** | Obtener credenciales de proveedores y servicios externos desde Vault al inicio y con renovación automática |

### Lo que el servicio NO hace

| Restricción | Justificación |
|-------------|---------------|
| No tiene base de datos de dominio propia (catálogo, stock, etc.) | Solo persiste logs de integración y estado de sagas; el dominio pertenece a los respectivos BCs |
| No valida reglas de negocio de dominio | Las invariantes (stock suficiente, ajuste válido, etc.) son validadas por los servicios de dominio correspondientes |
| No modifica datos de inventario directamente | Delega siempre a inventory-service; la saga coordina pero no escribe stock |
| No autentica usuarios finales | Keycloak/Kong gestionan la autenticación; este servicio solo verifica el token |
| No procesa respuestas asíncronas de proveedores FTP en tiempo real | El acuse de recibo FTP es responsabilidad de un proceso de reconciliación separado |

### Bounded Context BC-09

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                      Integration Service (BC-09)                                │
│                                                                                 │
│  ┌────────────────────┐   ┌──────────────────────┐   ┌─────────────────────┐   │
│  │  integration_logs  │   │ notification_dispatch │   │   saga_instance     │   │
│  │  tipo, proveedor   │   │  canal, intentos      │   │   saga_type, state  │   │
│  │  estado, payloads  │   │  estado, último_int.  │   │   current_step      │   │
│  └────────────────────┘   └──────────────────────┘   └────────┬────────────┘   │
│                                                                 │               │
│                                                        ┌────────▼────────────┐  │
│                                                        │   saga_step_log     │  │
│                                                        │   step_name, status │  │
│                                                        │   compensation_pl.  │  │
│                                                        └────────────────────┘   │
│                                                                                 │
│  ┌──────────────────────────────────────────────────────────────────────────┐   │
│  │                   Apache Camel Route Engine                              │   │
│  │                                                                          │   │
│  │  notification-route    ────►  Resilience4j CB  ────►  HTTP ext. notif.  │   │
│  │  reposicion-rest-route ────►  ACL por prov.   ────►  HTTP proveedor     │   │
│  │  reposicion-ftp-route  ────►  ACL por prov.   ────►  FTP/SFTP           │   │
│  │  saga-reposicion-route ────►  Camel Saga EIP + Narayana LRA             │   │
│  │  saga-ajuste-route     ────►  Camel Saga EIP + Narayana LRA             │   │
│  └──────────────────────────────────────────────────────────────────────────┘   │
│                                                                                 │
│  ┌────────────────────┐   ┌──────────────────────┐                             │
│  │  outbox (PG)       │   │  processed_message   │                             │
│  │  PENDING           │   │  (idempotencia)      │                             │
│  └────────┬───────────┘   └──────────────────────┘                             │
└──────────────────────────────────────────────────────────────────────────────┘
            │ (produce via outbox)               ▲ (consume)
            ▼                                    │
┌─────────────────────────────────┐  ┌───────────────────────────────────────┐
│  Apache Kafka                   │  │  Apache Kafka                         │
│  controlstock.integration.*     │  │  controlstock.integration.            │
│  .solicitud-reposicion-enviada  │  │  saga-events (step completions)       │
│  .solicitud-reposicion-fallida  │  │  controlstock.adjustment.ajuste-apro. │
│  .solicitud-reposicion-cancelada│  └───────────────────────────────────────┘
└─────────────────────────────────┘

Vault: spring-cloud-vault-config
  secret/integration-service/notificaciones → API_KEY, ENDPOINT
  secret/integration-service/proveedores/{id} → credentials
  secret/integration-service/ftp/{id} → host, user, password
```

### Flujo Saga-01 — Reposición de Inventario

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  Saga-01: Reposición de Inventario                                          │
│                                                                             │
│  Inicio: POST /integration/reposiciones  (body: SolicitudReposicionRequest) │
│                                                                             │
│  Step 1: integration-service → Proveedor (HTTP o FTP)                      │
│    ● Evento: SolicitudReposicionEnviada                                     │
│    ● Topic: controlstock.integration.solicitud-reposicion-enviada           │
│    ● Compensación: SolicitudReposicionCancelada (llamada HTTP al proveedor  │
│      o archivo de cancelación FTP)                                          │
│         │                                                                   │
│         ▼ (si Step 1 OK)                                                    │
│  Step 2: integration-service → inventory-service                            │
│    ● Comando: POST /internal/inventory/movements  (tipo: ENTRADA)           │
│    ● Evento: EntradaRegistrada (publicado por inventory-service)            │
│    ● Compensación: POST /inventory/movements/{id}/compensar                 │
│      → EntradaRevertida                                                     │
│         │                                                                   │
│         ▼ (si Step 2 OK)                                                    │
│  Step 3: Informacional — alert-service evalúa stock                         │
│    ● Evento: StockActualizado (publicado por inventory-service via Kafka)   │
│    ● No hay compensación (evaluación de alerta no requiere rollback)        │
│         │                                                                   │
│         ▼                                                                   │
│  Saga COMPLETADA                                                            │
│                                                                             │
│  Ante fallo en Step 2:                                                      │
│    → Compensar Step 1 (SolicitudReposicionCancelada)                        │
│    → Publicar SolicitudReposicionFallida                                    │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Flujo Saga-02 — Ajuste con Aprobación

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  Saga-02: Ajuste con Aprobación                                             │
│                                                                             │
│  Step 1: adjustment-service crea AdjustmentRequest en PENDIENTE             │
│    ● (iniciado por usuario via adjustment-service, no por integration-svc)  │
│    ● Compensación: POST /adjustments/{id}/compensar → AjusteRevertido       │
│         │                                                                   │
│         ▼ (supervisor aprueba)                                              │
│  Step 2: adjustment-service registra AdjustmentDecision                     │
│    ● Publica: AjusteAprobado (topic: controlstock.adjustment.ajuste-aprobado│
│      via Outbox)                                                            │
│    ● Compensación: POST /adjustments/{id}/compensar → AjusteRevertido       │
│         │                                                                   │
│         ▼ (inventory-service consume AjusteAprobado)                        │
│  Step 3: inventory-service aplica impacto de stock                          │
│    ● Compensación: POST /inventory/movements/{id}/compensar                 │
│      → EntradaRevertida / SalidaRevertida                                   │
│         │                                                                   │
│         ▼                                                                   │
│  Saga COMPLETADA                                                            │
│                                                                             │
│  Ante fallo en Step 3:                                                      │
│    → Compensar Step 2 (AjusteRevertido en adjustment-service)               │
│    → Compensar Step 1 (estado ERROR en adjustment-service)                  │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Base de datos

- **PostgreSQL 16** — schema `controlstock_integration` (integration_logs, notification_dispatch, saga_instance, saga_step_log, outbox, processed_message)
- **Vault** — spring-cloud-vault-config para credenciales de sistemas externos en tiempo de ejecución
- **Tecnología de acceso**: Spring Data R2DBC (reactivo) + Apache Camel Reactive Streams

---

## Prerrequisitos

| Prerrequisito | Documento de referencia | Verificación |
|--------------|------------------------|-------------|
| Etapa 0 — Infraestructura base completa | `DEV-ControlStock-00-infrastructure.md` | K3s corriendo; namespaces `apps`, `databases`, `kafka`, `infra` activos |
| Etapa 0c — Observabilidad configurada | `DEV-ControlStock-0c-observability.md` | Prometheus + Grafana + Jaeger activos |
| Etapa 1 — Bases de datos aprovisionadas | `DEV-ControlStock-01-databases.md` | Schema `controlstock_integration` en PostgreSQL con todas las tablas BC-09 |
| Etapa 2 — Scaffold generado | `DEV-ControlStock-02-scaffold.md` | Proyecto Maven `integration-service` generado (incluye dependencias Camel + Narayana) |
| Etapa 2b — Pipeline CI/CD configurado | `DEV-ControlStock-02b-cicd.md` | Job `integration-service` activo en Jenkins |
| **Etapa 3a — IAM Service corriendo** | `DEV-ControlStock-03-ms-iam-service.md` | Keycloak emitiendo tokens JWT para realm `controlstock` |
| **Etapa 3c — Inventory Service corriendo** | `DEV-ControlStock-03-ms-inventory-service.md` | Endpoints de compensación `POST /inventory/movements/{id}/compensar` disponibles |
| **Etapa 3d — Adjustment Service corriendo** | `DEV-ControlStock-03-ms-adjustment-service.md` | Endpoints de compensación `POST /adjustments/{id}/compensar` disponibles |
| **Etapa 3e — Alert Service corriendo** | `DEV-ControlStock-03-ms-alert-service.md` | Endpoint `POST /internal/notifications` disponible (o WireMock stub) |
| **Narayana LRA corriendo** | Etapa 0 — infra | LRA Coordinator accesible en `narayana-lra.infra.svc.cluster.local:50000` |
| Kafka (Strimzi KRaft) corriendo | Etapa 0 | Topics `controlstock.integration.*` y `controlstock.adjustment.*` creados |
| **Vault corriendo** | Etapa 0 | Secretos de integración cargados en paths `secret/integration-service/*` |

### Nota crítica sobre dependencias en desarrollo

En entorno de desarrollo K3s, los servicios de dominio (inventory-service, adjustment-service) pueden estar corriendo, pero **los sistemas externos deben ser simulados con WireMock**. Se despliega un pod WireMock en namespace `apps` con stubs para:
- `POST /api/notificaciones` — servicio externo de notificaciones
- `POST /api/proveedores/{id}/ordenes` — REST de proveedores
- FTP/SFTP — simulado con WireMock o un servidor SFTP en contenedor

```
http://wiremock.apps.svc.cluster.local:8080
```

Las compensaciones de saga requieren que inventory-service y adjustment-service estén corriendo (no en WireMock) para verificar idempotencia real. Si no están disponibles, usar stubs WireMock específicos para los endpoints de compensación.

### Verificación de prerrequisitos

```bash
# Verificar schema PostgreSQL integration
kubectl exec -n databases deploy/postgresql -- psql \
  -U controlstock_integration -d controlstock_integration \
  -c "\dt" | grep -E "integration_logs|notification_dispatch|saga_instance|saga_step_log|outbox|processed_message"

# Verificar Narayana LRA coordinator
kubectl exec -n infra deploy/narayana-lra -- \
  curl -s http://localhost:50000/lra-coordinator/api/v1/status | jq '.'
# Debe responder 200 OK

# Verificar Vault secretos de integración
kubectl exec -n infra deploy/vault -- \
  vault kv get secret/integration-service/notificaciones
# Debe mostrar: ENDPOINT, API_KEY

# Verificar topics Kafka integration
kubectl exec -n kafka deploy/kafka -- \
  kafka-topics.sh --list --bootstrap-server kafka:9092 \
  | grep "controlstock.integration"
# Salida esperada:
# controlstock.integration.solicitud-reposicion-enviada
# controlstock.integration.solicitud-reposicion-cancelada
# controlstock.integration.solicitud-reposicion-fallida

# Verificar inventory-service endpoint de compensación
curl -s -X POST \
  "http://<VPS_IP>:30083/inventory/movements/00000000-0000-0000-0000-000000000000/compensar" \
  -H "Authorization: Bearer $TOKEN" | jq '.error'
# Espera 404 (id no existente), no 503 — el servicio está UP

# Verificar adjustment-service endpoint de compensación
curl -s -X POST \
  "http://<VPS_IP>:30084/adjustments/00000000-0000-0000-0000-000000000000/compensar" \
  -H "Authorization: Bearer $TOKEN" | jq '.error'
# Espera 404 (id no existente), no 503

# Verificar WireMock funcionando (stubs externos)
curl -s "http://<VPS_IP>:30099/__admin/mappings" | jq '.mappings | length'
# Debe devolver ≥ 3 stubs configurados
```

---

## Ciclo de Desarrollo Incremental en K3s VPS dev

```
┌──────────────────────────────────────────────────────────────────┐
│               Ciclo de Desarrollo TDD — Integration Service      │
│                                                                  │
│  1. Escribir test RED (falla esperada)                           │
│         │  (camel-test-spring-junit5 + WireMock + StepVerifier)  │
│         ▼                                                        │
│  2. Implementar el mínimo código GREEN                           │
│         │  (Ruta Camel / UseCase / Port)                         │
│         ▼                                                        │
│  3. REFACTOR — mejorar diseño sin romper tests                   │
│         │                                                        │
│         ▼                                                        │
│  4. git push → Gitea webhook → Jenkins pipeline                  │
│         │                                                        │
│         ▼                                                        │
│  5. bumpImageTag → ArgoCD sync → K3s pod                        │
│         │                                                        │
│         ▼                                                        │
│  6. Verificar /actuator/health + prueba manual                   │
│                                                                  │
│  NOTA: No usar block() en ningún puente Camel ↔ Reactor.        │
│  Usar OBLIGATORIAMENTE camel-reactive-streams para bridge.       │
│                                                                  │
│  Condición mínima para primer deploy:                            │
│  - Dominio compila; contexto Spring arranca                      │
│  - GET /actuator/health/readiness → 200                          │
│  - Rutas Camel se inician sin error                              │
└──────────────────────────────────────────────────────────────────┘
```

### Orden de implementación incremental

| Incremento | Capa | Contenido | Condición de avance |
|-----------|------|-----------|-------------------|
| **I-1** | Dominio | Entidades: `SagaInstance`, `SagaStepLog`, `IntegrationLog`, `NotificationDispatch`; VOs: `SagaId`, `SagaType`, `SagaState`, `StepName`, `ProveedorId`; enums: `SagaType`, `SagaStepStatus`, `EstadoIntegracion`, `CanalNotificacion` | Tests dominio GREEN; invariantes de transición de estado de saga |
| **I-2** | Dominio | Eventos de dominio: `SolicitudReposicionEnviada`, `SolicitudReposicionCancelada`, `SolicitudReposicionFallida`; puertos: `NotificacionGateway`, `ReposicionProveedorGateway`, `ReposicionProveedorFtpGateway`, `SagaCoordinatorPort` | Interfaces compilando GREEN |
| **I-3** | Dominio | Puertos de repositorio: `SagaInstanceRepository`, `SagaStepLogRepository`, `IntegrationLogRepository`, `NotificationDispatchRepository`, `OutboxRepository`, `ProcessedMessageRepository` | Interfaces definidas; compilación GREEN |
| **I-4** | Aplicación | `EnviarNotificacionUseCase` (lógica de despacho + registro en notification_dispatch) | Tests aplicación con mocks GREEN |
| **I-5** | Aplicación | `IniciarReposicionUseCase` (inicia Saga-01: crea SagaInstance, delega a SagaCoordinatorPort) | Tests aplicación con mocks GREEN |
| **I-6** | Aplicación | `MonitorearSagaUseCase` (consulta estado saga, consulta steps) | Tests aplicación GREEN |
| **I-7** | Infraestructura | Ruta Camel `notification-route`: `direct:send-notification` → Resilience4j CB → HTTP → log | Tests camel-test-spring-junit5 + WireMock GREEN (success, 503, timeout) |
| **I-8** | Infraestructura | Ruta Camel `reposicion-rest-route`: `direct:send-reposicion-rest` → ACL → HTTP → log | Tests Camel + WireMock GREEN |
| **I-9** | Infraestructura | Ruta Camel `reposicion-ftp-route`: `direct:send-reposicion-ftp` → ACL → file → log | Tests Camel + embedded FTP GREEN |
| **I-10** | Infraestructura | Ruta Camel Saga `saga-reposicion-route`: Saga EIP + Narayana LRA; steps 1-2-3 + compensaciones | Tests saga happy path + failure GREEN |
| **I-11** | Infraestructura | Ruta Camel Saga `saga-ajuste-route`: Saga EIP + monitoring; compensaciones steps 3→2→1 | Tests saga-02 GREEN |
| **I-12** | Infraestructura | R2DBC adapters: `SagaInstanceR2dbc`, `IntegrationLogR2dbc`, `NotificationDispatchR2dbc`; Kafka consumer para saga events; OutboxRelay | Tests Testcontainers (PostgreSQL + Kafka) GREEN |
| **I-13** | API REST | Endpoints completos: `/integration/reposiciones`, `/integration/sagas`, `/internal/notifications` + `@ExceptionHandler` | Tests `@WebFluxTest` GREEN |
| **I-14** | Integración | E2E en K3s: Saga-01 completa; Saga-01 con fallo y compensación; Saga-02 completa | Suite de humo GREEN |

---

## Capa de Dominio

### Regla fundamental: sin dependencias de infraestructura

El dominio no tiene ninguna referencia a Apache Camel, Narayana LRA, R2DBC, Kafka ni Spring. Todos los tipos son puros Java 21 con tipos reactivos `Mono` y `Flux` (del proyecto Reactor) como únicos tipos de retorno de los puertos. Las rutas Camel y los adaptadores LRA viven exclusivamente en la capa de infraestructura.

### Entidades

#### `SagaInstance`

```java
// src/main/java/com/controlstock/integration/domain/model/SagaInstance.java
public class SagaInstance {
    private final SagaId sagaId;
    private final SagaType sagaType;
    private SagaState state;
    private int currentStep;
    private final Map<String, Object> payload;   // contexto compartido de la saga
    private final Instant createdAt;
    private Instant updatedAt;

    public static SagaInstance iniciar(SagaType type, Map<String, Object> payload) {
        return new SagaInstance(
            new SagaId(UUID.randomUUID()),
            type,
            SagaState.INICIADA,
            0,
            payload,
            Instant.now(),
            Instant.now()
        );
    }

    /**
     * Avanza al siguiente paso de la saga.
     * Invariante: no puede avanzar si la saga ya está COMPLETADA o FALLIDA.
     */
    public void avanzarPaso() {
        if (this.state == SagaState.COMPLETADA || this.state == SagaState.FALLIDA) {
            throw new SagaTransicionInvalidaException(this.sagaId, this.state, "avanzarPaso");
        }
        this.currentStep++;
        this.state = SagaState.EN_PROCESO;
        this.updatedAt = Instant.now();
    }

    /**
     * Marca la saga como completada exitosamente.
     */
    public void completar() {
        if (this.state == SagaState.FALLIDA) {
            throw new SagaTransicionInvalidaException(this.sagaId, this.state, "completar");
        }
        this.state = SagaState.COMPLETADA;
        this.updatedAt = Instant.now();
    }

    /**
     * Marca la saga como fallida; activa el proceso de compensación.
     */
    public void fallar() {
        this.state = SagaState.FALLIDA;
        this.updatedAt = Instant.now();
    }

    /**
     * Marca la saga como en proceso de compensación (rollback).
     */
    public void iniciarCompensacion() {
        this.state = SagaState.COMPENSANDO;
        this.updatedAt = Instant.now();
    }

    /**
     * Completa el proceso de compensación.
     */
    public void completarCompensacion() {
        if (this.state != SagaState.COMPENSANDO) {
            throw new SagaTransicionInvalidaException(
                this.sagaId, this.state, "completarCompensacion");
        }
        this.state = SagaState.COMPENSADA;
        this.updatedAt = Instant.now();
    }

    // Getters
    public SagaId getSagaId()           { return sagaId; }
    public SagaType getSagaType()       { return sagaType; }
    public SagaState getState()         { return state; }
    public int getCurrentStep()         { return currentStep; }
    public Map<String, Object> getPayload() { return Collections.unmodifiableMap(payload); }
    public Instant getCreatedAt()       { return createdAt; }
    public Instant getUpdatedAt()       { return updatedAt; }
}
```

#### `SagaStepLog`

```java
// src/main/java/com/controlstock/integration/domain/model/SagaStepLog.java
public class SagaStepLog {
    private final SagaStepLogId id;
    private final SagaId sagaId;
    private final StepName stepName;
    private final SagaStepStatus status;
    private final Map<String, Object> compensationPayload;  // nullable
    private final Instant executedAt;

    public static SagaStepLog registrar(
            SagaId sagaId,
            StepName stepName,
            SagaStepStatus status,
            Map<String, Object> compensationPayload) {
        return new SagaStepLog(
            new SagaStepLogId(UUID.randomUUID()),
            sagaId, stepName, status, compensationPayload, Instant.now()
        );
    }
    // Getters inmutables...
}
```

#### `IntegrationLog`

```java
// src/main/java/com/controlstock/integration/domain/model/IntegrationLog.java
public class IntegrationLog {
    private final IntegrationLogId id;
    private final String tipo;        // NOTIFICACION, REPOSICION_REST, REPOSICION_FTP
    private final ProveedorId proveedorId;   // nullable
    private final Map<String, Object> requestPayload;
    private final Map<String, Object> responsePayload;
    private final EstadoIntegracion estado;  // EXITO, FALLIDO, TIMEOUT
    private final Instant createdAt;

    public static IntegrationLog registrar(
            String tipo,
            ProveedorId proveedorId,
            Map<String, Object> requestPayload,
            Map<String, Object> responsePayload,
            EstadoIntegracion estado) {
        return new IntegrationLog(
            new IntegrationLogId(UUID.randomUUID()),
            tipo, proveedorId, requestPayload, responsePayload,
            estado, Instant.now()
        );
    }
    // Getters inmutables...
}
```

#### `NotificationDispatch`

```java
// src/main/java/com/controlstock/integration/domain/model/NotificationDispatch.java
public class NotificationDispatch {
    private final NotificationDispatchId id;
    private final UUID alertaId;
    private final CanalNotificacion canal;
    private final Map<String, Object> contenido;
    private EstadoDespacho estado;     // PENDIENTE, ENVIADO, FALLIDO
    private int intentos;
    private Instant ultimoIntento;
    private final Instant createdAt;

    public static NotificationDispatch crear(
            UUID alertaId,
            CanalNotificacion canal,
            Map<String, Object> contenido) {
        return new NotificationDispatch(
            new NotificationDispatchId(UUID.randomUUID()),
            alertaId, canal, contenido,
            EstadoDespacho.PENDIENTE, 0, null, Instant.now()
        );
    }

    /**
     * Registra un intento de envío, sea exitoso o fallido.
     * Invariante: no se puede enviar si ya está en estado ENVIADO.
     */
    public void registrarIntento(boolean exitoso) {
        if (this.estado == EstadoDespacho.ENVIADO) {
            throw new NotificacionYaEnviadaException(this.id);
        }
        this.intentos++;
        this.ultimoIntento = Instant.now();
        this.estado = exitoso ? EstadoDespacho.ENVIADO : EstadoDespacho.FALLIDO;
    }

    // Getters...
    public int getIntentos()                { return intentos; }
    public EstadoDespacho getEstado()       { return estado; }
    public Instant getUltimoIntento()       { return ultimoIntento; }
}
```

### Value Objects

```java
// SagaId.java
public record SagaId(UUID value) {
    public SagaId { Objects.requireNonNull(value, "sagaId no puede ser nulo"); }
}

// SagaType.java
public enum SagaType {
    REPOSICION_INVENTARIO,   // Saga-01
    AJUSTE_CON_APROBACION    // Saga-02
}

// SagaState.java
public enum SagaState {
    INICIADA, EN_PROCESO, COMPLETADA, FALLIDA, COMPENSANDO, COMPENSADA
}

// SagaStepStatus.java
public enum SagaStepStatus {
    COMPLETADO, FALLIDO, COMPENSADO, COMPENSACION_FALLIDA
}

// EstadoIntegracion.java
public enum EstadoIntegracion { EXITO, FALLIDO, TIMEOUT }

// CanalNotificacion.java
public enum CanalNotificacion { EMAIL, WHATSAPP, PUSH }

// EstadoDespacho.java
public enum EstadoDespacho { PENDIENTE, ENVIADO, FALLIDO }

// ProveedorId.java
public record ProveedorId(UUID value) {
    public ProveedorId { Objects.requireNonNull(value, "proveedorId no puede ser nulo"); }
}

// StepName.java
public record StepName(String value) {
    public StepName {
        Objects.requireNonNull(value, "stepName no puede ser nulo");
        if (value.isBlank()) throw new IllegalArgumentException("stepName no puede ser vacío");
    }
}
```

### Puertos (interfaces del dominio)

```java
// src/main/java/com/controlstock/integration/domain/port/out/NotificacionGateway.java
/**
 * Puerto de salida: enviar notificación al servicio externo.
 * La implementación usa Apache Camel (notification-route).
 * NUNCA usar block() — retorna Mono reactivo.
 */
public interface NotificacionGateway {
    Mono<NotificacionResult> enviar(NotificacionRequest request);
}

// src/main/java/com/controlstock/integration/domain/port/out/ReposicionProveedorGateway.java
/**
 * Puerto de salida: enviar solicitud de reposición a proveedor REST.
 * Implementación con Camel HTTP + ACL por proveedor.
 */
public interface ReposicionProveedorGateway {
    Mono<ReposicionResult> enviar(SolicitudReposicion solicitud, ProveedorId proveedorId);
}

// src/main/java/com/controlstock/integration/domain/port/out/ReposicionProveedorFtpGateway.java
/**
 * Puerto de salida: enviar solicitud de reposición via FTP/SFTP.
 * Implementación con Camel file/ftp component.
 */
public interface ReposicionProveedorFtpGateway {
    Mono<ReposicionResult> enviar(SolicitudReposicion solicitud, ProveedorId proveedorId);
}

// src/main/java/com/controlstock/integration/domain/port/out/SagaCoordinatorPort.java
/**
 * Puerto de salida: coordinar ejecución de saga.
 * Implementación con Apache Camel Saga EIP + Narayana LRA.
 * NUNCA usar block() — todos los métodos retornan Mono/Flux reactivos.
 */
public interface SagaCoordinatorPort {
    Mono<SagaInstance> iniciarSaga(SagaType type, Map<String, Object> payload);
    Mono<SagaInstance> ejecutarPaso(SagaId sagaId, StepName stepName);
    Mono<SagaInstance> compensar(SagaId sagaId);
    Mono<SagaInstance> obtenerEstado(SagaId sagaId);
    Flux<SagaInstance> listarSagas(SagaType type, SagaState state);
}
```

### Repositorios (puertos de persistencia)

```java
// SagaInstanceRepository.java
public interface SagaInstanceRepository {
    Mono<SagaInstance> save(SagaInstance saga);
    Mono<SagaInstance> findById(SagaId sagaId);
    Flux<SagaInstance> findByTypeAndState(SagaType type, SagaState state);
    Mono<SagaInstance> update(SagaInstance saga);
}

// SagaStepLogRepository.java
public interface SagaStepLogRepository {
    Mono<SagaStepLog> save(SagaStepLog stepLog);
    Flux<SagaStepLog> findBySagaId(SagaId sagaId);
    Flux<SagaStepLog> findBySagaIdOrderByExecutedAtDesc(SagaId sagaId);
}

// IntegrationLogRepository.java
public interface IntegrationLogRepository {
    Mono<IntegrationLog> save(IntegrationLog log);
    Flux<IntegrationLog> findByProveedorId(ProveedorId proveedorId);
}

// NotificationDispatchRepository.java
public interface NotificationDispatchRepository {
    Mono<NotificationDispatch> save(NotificationDispatch dispatch);
    Mono<NotificationDispatch> findById(NotificationDispatchId id);
    Mono<NotificationDispatch> findByAlertaId(UUID alertaId);
    Mono<NotificationDispatch> update(NotificationDispatch dispatch);
}
```

### Excepciones de dominio

```java
public class SagaTransicionInvalidaException extends RuntimeException { ... }
public class SagaNoEncontradaException extends RuntimeException { ... }
public class NotificacionYaEnviadaException extends RuntimeException { ... }
public class ProveedorNoConfiguradoException extends RuntimeException { ... }
public class SagaStepFallidoException extends RuntimeException {
    private final SagaId sagaId;
    private final StepName stepName;
    private final int stepNumber;
    // Constructor + getters
}
```

---

## Capa de Aplicación

### Regla: sin Camel, sin LRA, sin R2DBC

Los use cases dependen solo de los puertos definidos en el dominio. Las rutas Camel y los adaptadores LRA son detalles de infraestructura que implementan esos puertos. Los use cases son tipos Java puros inyectados via constructor.

### Use Cases

#### `EnviarNotificacionUseCase`

```java
// src/main/java/com/controlstock/integration/application/usecase/EnviarNotificacionUseCase.java
@Service
@RequiredArgsConstructor
public class EnviarNotificacionUseCase {

    private final NotificacionGateway notificacionGateway;
    private final NotificationDispatchRepository dispatchRepository;
    private final IntegrationLogRepository integrationLogRepository;

    /**
     * Recibe solicitud de notificación de alert-service,
     * registra el dispatch, delega al gateway y actualiza el estado.
     *
     * Flujo reactivo: NUNCA se llama block().
     * El bridge Camel usa camel-reactive-streams.
     */
    public Mono<NotificationDispatch> ejecutar(EnviarNotificacionCommand command) {
        NotificationDispatch dispatch = NotificationDispatch.crear(
            command.alertaId(), command.canal(), command.contenido()
        );

        return dispatchRepository.save(dispatch)
            .flatMap(saved ->
                notificacionGateway.enviar(
                    NotificacionRequest.from(command, saved.getId()))
                .flatMap(result -> {
                    saved.registrarIntento(result.exitoso());
                    IntegrationLog log = IntegrationLog.registrar(
                        "NOTIFICACION", null,
                        command.toMap(), result.toMap(),
                        result.exitoso() ? EstadoIntegracion.EXITO : EstadoIntegracion.FALLIDO
                    );
                    return integrationLogRepository.save(log)
                        .then(dispatchRepository.update(saved));
                })
                .onErrorResume(ex -> {
                    saved.registrarIntento(false);
                    IntegrationLog log = IntegrationLog.registrar(
                        "NOTIFICACION", null,
                        command.toMap(), Map.of("error", ex.getMessage()),
                        ex instanceof CalloutTimeoutException
                            ? EstadoIntegracion.TIMEOUT : EstadoIntegracion.FALLIDO
                    );
                    return integrationLogRepository.save(log)
                        .then(dispatchRepository.update(saved));
                })
            );
    }
}
```

#### `IniciarReposicionUseCase` (Orquestador Saga-01)

```java
// src/main/java/com/controlstock/integration/application/usecase/IniciarReposicionUseCase.java
@Service
@RequiredArgsConstructor
public class IniciarReposicionUseCase {

    private final SagaCoordinatorPort sagaCoordinator;
    private final SagaInstanceRepository sagaInstanceRepository;
    private final OutboxRepository outboxRepository;

    /**
     * Inicia Saga-01: crea SagaInstance y delega la orquestación
     * al SagaCoordinatorPort (implementado por CamelSagaAdapter con LRA).
     */
    public Mono<SagaInstance> ejecutar(IniciarReposicionCommand command) {
        Map<String, Object> payload = Map.of(
            "productoId", command.productoId().toString(),
            "cantidad", command.cantidad().toString(),
            "proveedorId", command.proveedorId().toString(),
            "tipoConexion", command.tipoConexion().name(),  // REST o FTP
            "usuarioId", command.usuarioId().toString()
        );

        return sagaCoordinator.iniciarSaga(SagaType.REPOSICION_INVENTARIO, payload)
            .flatMap(sagaInstance ->
                sagaCoordinator.ejecutarPaso(
                    sagaInstance.getSagaId(),
                    new StepName("ENVIAR_A_PROVEEDOR")
                )
            );
    }
}
```

#### `MonitorearSagaUseCase`

```java
@Service
@RequiredArgsConstructor
public class MonitorearSagaUseCase {

    private final SagaInstanceRepository sagaInstanceRepository;
    private final SagaStepLogRepository sagaStepLogRepository;

    public Mono<SagaInstance> obtenerSaga(SagaId sagaId) {
        return sagaInstanceRepository.findById(sagaId)
            .switchIfEmpty(Mono.error(new SagaNoEncontradaException(sagaId)));
    }

    public Flux<SagaInstance> listarSagas(SagaType type, SagaState state) {
        return sagaInstanceRepository.findByTypeAndState(type, state);
    }

    public Flux<SagaStepLog> obtenerPasos(SagaId sagaId) {
        return sagaStepLogRepository.findBySagaIdOrderByExecutedAtDesc(sagaId);
    }
}
```

#### `SagaOrchestratorUseCase` (genérico por tipo)

```java
@Service
@RequiredArgsConstructor
public class SagaOrchestratorUseCase {

    private final SagaCoordinatorPort sagaCoordinator;
    private final SagaInstanceRepository sagaInstanceRepository;
    private final SagaStepLogRepository sagaStepLogRepository;

    /**
     * Ejecuta el siguiente paso de una saga.
     * Llamado por el endpoint interno POST /integration/sagas/{sagaId}/ejecutar.
     * Si el paso falla, inicia la compensación en orden inverso.
     */
    public Mono<SagaInstance> ejecutarPaso(SagaId sagaId, StepName stepName) {
        return sagaCoordinator.ejecutarPaso(sagaId, stepName)
            .onErrorResume(SagaStepFallidoException.class, ex ->
                sagaCoordinator.compensar(ex.getSagaId())
                    .doOnSuccess(compensada ->
                        log.warn("Saga {} compensada tras fallo en paso {}",
                            ex.getSagaId(), ex.getStepName()))
            );
    }
}
```

### Commands y DTOs de aplicación

```java
// IniciarReposicionCommand.java
public record IniciarReposicionCommand(
    ProductoId productoId,
    Cantidad cantidad,
    ProveedorId proveedorId,
    TipoConexionProveedor tipoConexion,  // REST o FTP
    UUID usuarioId
) {}

// EnviarNotificacionCommand.java
public record EnviarNotificacionCommand(
    UUID alertaId,
    CanalNotificacion canal,
    Map<String, Object> contenido
) {
    public Map<String, Object> toMap() { return contenido; }
}

// NotificacionRequest.java
public record NotificacionRequest(
    NotificationDispatchId dispatchId,
    UUID alertaId,
    CanalNotificacion canal,
    Map<String, Object> contenido
) {
    public static NotificacionRequest from(
            EnviarNotificacionCommand cmd,
            NotificationDispatchId dispatchId) {
        return new NotificacionRequest(dispatchId, cmd.alertaId(), cmd.canal(), cmd.contenido());
    }
}

// TipoConexionProveedor.java
public enum TipoConexionProveedor { REST, FTP }
```

---

## Capa de Infraestructura

### Regla crítica: bridge Camel ↔ Reactor

**NUNCA usar `block()` en el puente entre Apache Camel y Project Reactor.** El mecanismo obligatorio es `camel-reactive-streams` (componente `reactive-streams:`), que permite a Camel producir y consumir `Publisher<T>` sin bloqueo. La llamada a `block()` en cualquier hilo de un CamelContext produciría deadlock bajo carga y viola el contrato reactivo del servicio.

```xml
<!-- pom.xml — dependencias obligatorias -->
<dependency>
    <groupId>org.apache.camel.springboot</groupId>
    <artifactId>camel-reactive-streams-starter</artifactId>
</dependency>
<dependency>
    <groupId>org.apache.camel.springboot</groupId>
    <artifactId>camel-http-starter</artifactId>
</dependency>
<dependency>
    <groupId>org.apache.camel.springboot</groupId>
    <artifactId>camel-ftp-starter</artifactId>
</dependency>
<dependency>
    <groupId>org.apache.camel.springboot</groupId>
    <artifactId>camel-saga-starter</artifactId>
</dependency>
<dependency>
    <groupId>org.apache.camel.springboot</groupId>
    <artifactId>camel-resilience4j-starter</artifactId>
</dependency>
<dependency>
    <groupId>org.apache.camel.springboot</groupId>
    <artifactId>camel-test-spring-junit5</artifactId>
    <scope>test</scope>
</dependency>
<dependency>
    <groupId>org.narayana.lra</groupId>
    <artifactId>narayana-lra</artifactId>
    <version>7.x</version>
</dependency>
```

### Rutas Camel

#### `notification-route` — Envío a servicio externo de notificaciones

```java
// src/main/java/com/controlstock/integration/infrastructure/camel/NotificationRoute.java
@Component
public class NotificationRoute extends RouteBuilder {

    @Value("${integration.notificaciones.endpoint}")  // inyectado desde Vault via spring-cloud-vault
    private String notificacionesEndpoint;

    @Override
    public void configure() throws Exception {

        // Circuit Breaker global para el servicio de notificaciones
        resilience4jConfiguration("notificaciones-cb")
            .failureRateThreshold(50)
            .slowCallRateThreshold(80)
            .slowCallDurationThreshold(10000)       // 10s
            .waitDurationInOpenState(30000)
            .slidingWindowSize(10)
            .end();

        // Ruta principal: direct:send-notification
        // Entrada: NotificacionRequest (body)
        // Salida: NotificacionResult
        from("direct:send-notification")
            .routeId("notification-route")
            .circuitBreaker()
                .resilience4jConfiguration()
                    .timeoutEnabled(true)
                    .timeoutDuration(10000)         // 10s timeout
                .end()
                .redeliveryPolicy(policy -> policy
                    .maximumRedeliveries(3)
                    .redeliveryDelay(1000)          // 1s inicial
                    .backOffMultiplier(4.0)         // x4: 1s, 4s, 16s
                    .useExponentialBackOff())
                .to("bean:notificacionRequestMapper?method=toHttpBody")
                .setHeader("Content-Type", constant("application/json"))
                .setHeader("X-API-Key",
                    simple("${properties:integration.notificaciones.api-key}"))
                .toD("${exchangeProperty.notificacionesEndpoint}")
                .to("bean:notificacionResponseMapper?method=toResult")
            .onFallback()
                .process(exchange -> {
                    Exception cause = exchange.getProperty(
                        Exchange.EXCEPTION_CAUGHT, Exception.class);
                    exchange.getIn().setBody(
                        NotificacionResult.fallido(cause.getMessage()));
                })
            .end()
            .to("direct:log-notification");

        // Sub-ruta: registrar en notification_dispatch (reactivo via camel-reactive-streams)
        from("direct:log-notification")
            .routeId("notification-log-route")
            .to("reactive-streams:notification-log-stream");
        // El subscriber reactivo lo procesa NotificationDispatchAdapter
    }
}
```

#### `reposicion-rest-route` — ACL para proveedores REST

```java
// src/main/java/com/controlstock/integration/infrastructure/camel/ReposicionRestRoute.java
@Component
public class ReposicionRestRoute extends RouteBuilder {

    @Override
    public void configure() throws Exception {

        // ACL por proveedor: el ProveedorAclRegistry mapea proveedorId → transformador
        from("direct:send-reposicion-rest")
            .routeId("reposicion-rest-route")
            .process(exchange -> {
                SolicitudReposicion solicitud = exchange.getIn()
                    .getBody(SolicitudReposicion.class);
                ProveedorId proveedorId = exchange.getIn()
                    .getHeader("proveedorId", ProveedorId.class);
                // Aplicar ACL: traducir al modelo del proveedor específico
                Object proveedorDto = proveedorAclRegistry
                    .traducir(solicitud, proveedorId);
                exchange.getIn().setBody(proveedorDto);
                exchange.setProperty("proveedorId", proveedorId);
            })
            .circuitBreaker()
                .resilience4jConfiguration()
                    .timeoutEnabled(true)
                    .timeoutDuration(10000)
                .end()
                .redeliveryPolicy(policy -> policy
                    .maximumRedeliveries(3)
                    .redeliveryDelay(1000)
                    .backOffMultiplier(4.0)
                    .useExponentialBackOff())
                .toD("${exchangeProperty.proveedorRestEndpoint}")
                .to("bean:reposicionResponseMapper?method=toResult")
            .onFallback()
                .process(exchange -> {
                    Exception cause = exchange.getProperty(
                        Exchange.EXCEPTION_CAUGHT, Exception.class);
                    exchange.getIn().setBody(
                        ReposicionResult.fallido(cause.getMessage()));
                })
            .end()
            .to("reactive-streams:integration-log-stream");
    }
}
```

#### `reposicion-ftp-route` — ACL para proveedores FTP/SFTP

```java
// src/main/java/com/controlstock/integration/infrastructure/camel/ReposicionFtpRoute.java
@Component
public class ReposicionFtpRoute extends RouteBuilder {

    @Override
    public void configure() throws Exception {

        from("direct:send-reposicion-ftp")
            .routeId("reposicion-ftp-route")
            .process(exchange -> {
                SolicitudReposicion solicitud = exchange.getIn()
                    .getBody(SolicitudReposicion.class);
                ProveedorId proveedorId = exchange.getIn()
                    .getHeader("proveedorId", ProveedorId.class);
                // ACL: generar contenido de archivo (CSV / EDI) según formato del proveedor
                String fileContent = proveedorFtpAclRegistry
                    .generarArchivo(solicitud, proveedorId);
                String fileName = "reposicion-"
                    + solicitud.getSolicitudId() + ".csv";
                exchange.getIn().setBody(fileContent);
                exchange.getIn().setHeader(Exchange.FILE_NAME, fileName);
                exchange.setProperty("proveedorId", proveedorId);
            })
            // Vault provee: host, user, password, directory via dynamic endpoint
            .toD("sftp:${exchangeProperty.ftpHost}/${exchangeProperty.ftpDir}"
                + "?username=${exchangeProperty.ftpUser}"
                + "&password=${exchangeProperty.ftpPassword}"
                + "&disconnect=true")
            .process(exchange -> {
                exchange.getIn().setBody(
                    ReposicionResult.exitoFtp(
                        exchange.getIn().getHeader(Exchange.FILE_NAME, String.class)));
            })
            .to("reactive-streams:integration-log-stream");
    }
}
```

#### `saga-reposicion-route` — Camel Saga EIP + Narayana LRA (Saga-01)

```java
// src/main/java/com/controlstock/integration/infrastructure/camel/SagaReposicionRoute.java
@Component
public class SagaReposicionRoute extends RouteBuilder {

    @Override
    public void configure() throws Exception {

        // Compensación Step 1: cancelar solicitud enviada al proveedor
        from("direct:compensar-envio-proveedor")
            .routeId("compensar-envio-proveedor")
            .log("Compensando Step 1 (envio proveedor) para saga ${header.CamelSagaId}")
            .to("bean:compensacionProveedorHandler?method=cancelar")
            .to("reactive-streams:saga-compensation-stream");

        // Compensación Step 2: revertir entrada en inventory-service
        from("direct:compensar-entrada-inventario")
            .routeId("compensar-entrada-inventario")
            .log("Compensando Step 2 (entrada inventario) para saga ${header.CamelSagaId}")
            .to("bean:compensacionInventarioHandler?method=revertirEntrada")
            .to("reactive-streams:saga-compensation-stream");

        // Ruta principal de Saga-01
        from("direct:saga-reposicion")
            .routeId("saga-reposicion-route")
            .saga()
                .propagation(SagaPropagation.REQUIRED)
                .option("sagaId", header("sagaId"))
            // Step 1: enviar al proveedor
            .saga()
                .compensation("direct:compensar-envio-proveedor")
                .option("solicitudId", body())
            .to("direct:send-reposicion-dispatch")   // determina REST o FTP y enruta
            .process(exchange -> {
                // Actualizar saga_step_log Step 1 COMPLETADO
                exchange.setProperty("step1Result",
                    exchange.getIn().getBody(ReposicionResult.class));
            })
            .to("reactive-streams:saga-step-completed-stream")
            // Step 2: registrar entrada en inventory-service
            .saga()
                .compensation("direct:compensar-entrada-inventario")
                .option("movimientoId", exchangeProperty("movimientoId"))
            .to("direct:registrar-entrada-inventario")
            .process(exchange -> {
                // Actualizar saga_step_log Step 2 COMPLETADO
            })
            .to("reactive-streams:saga-step-completed-stream")
            // Step 3: informacional — alert-service evalúa stock via Kafka (sin compensación)
            .end()
            .to("reactive-streams:saga-completed-stream");
    }
}
```

#### `saga-ajuste-route` — Camel Saga EIP (Saga-02)

```java
// src/main/java/com/controlstock/integration/infrastructure/camel/SagaAjusteRoute.java
@Component
public class SagaAjusteRoute extends RouteBuilder {

    @Override
    public void configure() throws Exception {

        // Compensación Step 2: revertir ajuste en adjustment-service
        from("direct:compensar-ajuste-aprobado")
            .routeId("compensar-ajuste-aprobado")
            .to("bean:compensacionAjusteHandler?method=revertirAjuste")
            .to("reactive-streams:saga-compensation-stream");

        // Compensación Step 3: revertir impacto de stock en inventory-service
        from("direct:compensar-impacto-stock-ajuste")
            .routeId("compensar-impacto-stock-ajuste")
            .to("bean:compensacionInventarioHandler?method=revertirMovimientoAjuste")
            .to("reactive-streams:saga-compensation-stream");

        // Saga-02: el integration-service monitorea y coordina
        // el flujo iniciado externamente (adjustment-service → inventory-service)
        // Kafka consumer: consume AjusteAprobado y monitorea ejecución de Step 3
        from("kafka:controlstock.adjustment.ajuste-aprobado"
            + "?brokers={{kafka.bootstrap-servers}}"
            + "&groupId=integration-service-saga02"
            + "&autoOffsetReset=earliest")
            .routeId("saga-ajuste-monitor-route")
            .idempotentConsumer(
                header("kafka.KEY"),
                idempotentRepository)   // processed_message table via R2DBC
            .saga()
                .propagation(SagaPropagation.REQUIRED)
                .option("ajusteId", body())
            .saga()
                .compensation("direct:compensar-ajuste-aprobado")
            .to("reactive-streams:saga-ajuste-step2-stream")
            // Monitorear aplicación del stock — si falla, compensar
            .to("reactive-streams:saga-ajuste-step3-monitor-stream")
            .end();
    }
}
```

### Adaptador de Saga (implementa `SagaCoordinatorPort`)

```java
// src/main/java/com/controlstock/integration/infrastructure/camel/CamelSagaAdapter.java
@Component
@RequiredArgsConstructor
public class CamelSagaAdapter implements SagaCoordinatorPort {

    private final ProducerTemplate producerTemplate;
    private final SagaInstanceRepository sagaInstanceRepository;
    private final SagaStepLogRepository sagaStepLogRepository;
    private final ReactiveStreamsComponent reactiveStreams;   // camel-reactive-streams

    /**
     * Inicia una saga: persiste SagaInstance y lanza la ruta Camel correspondiente.
     * Usa camel-reactive-streams para bridge sin block().
     */
    @Override
    public Mono<SagaInstance> iniciarSaga(SagaType type, Map<String, Object> payload) {
        SagaInstance instance = SagaInstance.iniciar(type, payload);
        return sagaInstanceRepository.save(instance)
            .flatMap(saved -> {
                String routeEndpoint = resolveRouteEndpoint(type);
                // camel-reactive-streams: sendBody devuelve Publisher sin block()
                return Mono.fromCompletionStage(
                    producerTemplate.asyncSendBodyAndHeaders(
                        routeEndpoint,
                        payload,
                        Map.of("sagaId", saved.getSagaId().value().toString())
                    )
                ).thenReturn(saved);
            });
    }

    @Override
    public Mono<SagaInstance> ejecutarPaso(SagaId sagaId, StepName stepName) {
        return sagaInstanceRepository.findById(sagaId)
            .flatMap(saga -> {
                saga.avanzarPaso();
                return sagaInstanceRepository.update(saga)
                    .flatMap(updated -> {
                        SagaStepLog stepLog = SagaStepLog.registrar(
                            sagaId, stepName, SagaStepStatus.COMPLETADO, null);
                        return sagaStepLogRepository.save(stepLog)
                            .thenReturn(updated);
                    });
            });
    }

    @Override
    public Mono<SagaInstance> compensar(SagaId sagaId) {
        return sagaInstanceRepository.findById(sagaId)
            .flatMap(saga -> {
                saga.iniciarCompensacion();
                return sagaInstanceRepository.update(saga)
                    .flatMap(updated ->
                        // Lanzar compensaciones en orden inverso vía Camel
                        Mono.fromCompletionStage(
                            producerTemplate.asyncSendBodyAndHeaders(
                                "direct:compensar-" + saga.getSagaType().name().toLowerCase(),
                                saga.getPayload(),
                                Map.of("sagaId", sagaId.value().toString())
                            )
                        ).thenReturn(updated)
                    );
            });
    }

    private String resolveRouteEndpoint(SagaType type) {
        return switch (type) {
            case REPOSICION_INVENTARIO -> "direct:saga-reposicion";
            case AJUSTE_CON_APROBACION -> "direct:saga-ajuste";
        };
    }
}
```

### Adaptadores R2DBC

```java
// src/main/java/com/controlstock/integration/infrastructure/r2dbc/SagaInstanceR2dbcAdapter.java
@Repository
@RequiredArgsConstructor
public class SagaInstanceR2dbcAdapter implements SagaInstanceRepository {

    private final R2dbcSagaInstanceDao dao;   // Spring Data R2DBC Repository interface

    @Override
    public Mono<SagaInstance> save(SagaInstance saga) {
        return dao.save(SagaInstanceEntity.from(saga))
            .map(SagaInstanceEntity::toDomain);
    }

    @Override
    public Mono<SagaInstance> findById(SagaId sagaId) {
        return dao.findById(sagaId.value())
            .map(SagaInstanceEntity::toDomain)
            .switchIfEmpty(Mono.error(new SagaNoEncontradaException(sagaId)));
    }

    @Override
    public Flux<SagaInstance> findByTypeAndState(SagaType type, SagaState state) {
        return dao.findBySagaTypeAndState(type.name(), state.name())
            .map(SagaInstanceEntity::toDomain);
    }

    @Override
    public Mono<SagaInstance> update(SagaInstance saga) {
        return dao.save(SagaInstanceEntity.from(saga))
            .map(SagaInstanceEntity::toDomain);
    }
}

// Entidad R2DBC
@Table("saga_instance")
public class SagaInstanceEntity {
    @Id UUID sagaId;
    String sagaType;
    String state;
    int currentStep;
    @Column("payload") String payloadJson;
    Instant createdAt;
    Instant updatedAt;

    public static SagaInstanceEntity from(SagaInstance domain) { ... }
    public SagaInstance toDomain() { ... }
}
```

### Adaptador de Notificaciones (implementa `NotificacionGateway`)

```java
// src/main/java/com/controlstock/integration/infrastructure/camel/CamelNotificacionGateway.java
@Component
@RequiredArgsConstructor
public class CamelNotificacionGateway implements NotificacionGateway {

    private final ProducerTemplate producerTemplate;

    /**
     * Delega la llamada a la ruta Camel notification-route.
     * USA camel-reactive-streams: NO hay block() en ningún punto.
     */
    @Override
    public Mono<NotificacionResult> enviar(NotificacionRequest request) {
        // asyncRequestBodyAndHeaders devuelve Future sin bloquear
        return Mono.fromCompletionStage(
            producerTemplate.asyncRequestBodyAndHeaders(
                "direct:send-notification",
                request,
                Map.of("alertaId", request.alertaId().toString())
            )
        ).map(response -> (NotificacionResult) response);
    }
}
```

### Configuración de Resilience4j para Camel

```yaml
# src/main/resources/application.yaml
camel:
  resilience4j:
    notificaciones-cb:
      failure-rate-threshold: 50
      slow-call-rate-threshold: 80
      slow-call-duration-threshold: PT10S
      wait-duration-in-open-state: PT30S
      sliding-window-size: 10
      permitted-number-of-calls-in-half-open-state: 3

integration:
  notificaciones:
    endpoint: "${vault:secret/integration-service/notificaciones/endpoint}"
    api-key: "${vault:secret/integration-service/notificaciones/api-key}"
  lra:
    coordinator-url: "http://narayana-lra.infra.svc.cluster.local:50000/lra-coordinator"
```

### Configuración Narayana LRA

```yaml
# application.yaml — configuración LRA
mp:
  lra:
    coordinator:
      url: http://narayana-lra.infra.svc.cluster.local:50000/lra-coordinator
    participant:
      url: http://integration-service.apps.svc.cluster.local:8089
```

### Esquema de base de datos BC-09

```sql
-- Schema: controlstock_integration

CREATE TABLE integration_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tipo VARCHAR(50) NOT NULL,
    proveedor_id UUID,
    request_payload JSONB,
    response_payload JSONB,
    estado VARCHAR(30) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE notification_dispatch (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    alerta_id UUID NOT NULL,
    canal VARCHAR(50) NOT NULL,
    contenido JSONB NOT NULL,
    estado VARCHAR(30) NOT NULL DEFAULT 'PENDIENTE'
        CHECK (estado IN ('PENDIENTE','ENVIADO','FALLIDO')),
    intentos INTEGER NOT NULL DEFAULT 0,
    ultimo_intento TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE saga_instance (
    saga_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    saga_type VARCHAR(100) NOT NULL,
    state VARCHAR(50) NOT NULL,
    current_step INTEGER NOT NULL DEFAULT 0,
    payload JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_saga_instance_type_state ON saga_instance(saga_type, state);

CREATE TABLE saga_step_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    saga_id UUID NOT NULL REFERENCES saga_instance(saga_id),
    step_name VARCHAR(100) NOT NULL,
    status VARCHAR(50) NOT NULL,
    compensation_payload JSONB,
    executed_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_saga_step_log_saga_id ON saga_step_log(saga_id);

CREATE TABLE outbox (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    aggregate_type VARCHAR(100) NOT NULL,
    aggregate_id UUID NOT NULL,
    event_type VARCHAR(100) NOT NULL,
    payload JSONB NOT NULL,
    estado VARCHAR(20) NOT NULL DEFAULT 'PENDING'
        CHECK (estado IN ('PENDING','PUBLISHED','FAILED')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    published_at TIMESTAMPTZ
);

CREATE TABLE processed_message (
    message_id VARCHAR(255) PRIMARY KEY,
    processed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    consumer_group VARCHAR(100) NOT NULL
);
```

---

## API REST

### Endpoints públicos (vía Kong)

| Método | Path | Roles | Descripción |
|--------|------|-------|-------------|
| `POST` | `/integration/reposiciones` | `OPERADOR`, `ADMIN` | Inicia Saga-01 — solicitud de reposición de inventario |
| `GET` | `/integration/sagas` | `ADMIN`, `SUPERVISOR` | Lista instancias de sagas (filtro: type, state) |
| `GET` | `/integration/sagas/{sagaId}` | `ADMIN`, `SUPERVISOR`, `OPERADOR` | Obtiene estado actual de una saga |
| `POST` | `/integration/sagas/{sagaId}/ejecutar` | `ADMIN` | Ejecuta/reanuda el siguiente paso de una saga (uso interno/administrativo) |

### Endpoints internos (NO vía Kong — DNS interno K3s únicamente)

| Método | Path | Caller | Descripción |
|--------|------|--------|-------------|
| `POST` | `/internal/notifications` | `alert-service` | Recibe solicitud de envío de notificación |

### Contratos de API

#### `POST /integration/reposiciones`

```
Request:
{
  "productoId": "uuid",
  "cantidad": 50,
  "proveedorId": "uuid",
  "tipoConexion": "REST",         // REST | FTP
  "notas": "Reposición urgente"
}

Response 202 Accepted:
{
  "sagaId": "uuid",
  "sagaType": "REPOSICION_INVENTARIO",
  "state": "EN_PROCESO",
  "currentStep": 1,
  "createdAt": "2025-01-01T10:00:00Z"
}

Response 400 Bad Request:
{
  "error": "PROVEEDOR_NO_CONFIGURADO",
  "message": "No existe configuración para proveedorId: {uuid}"
}
```

#### `GET /integration/sagas`

```
Query params:
  type: REPOSICION_INVENTARIO | AJUSTE_CON_APROBACION (opcional)
  state: INICIADA | EN_PROCESO | COMPLETADA | FALLIDA | COMPENSANDO | COMPENSADA (opcional)
  page: 0 (default)
  size: 20 (default)

Response 200 OK:
{
  "content": [
    {
      "sagaId": "uuid",
      "sagaType": "REPOSICION_INVENTARIO",
      "state": "COMPLETADA",
      "currentStep": 3,
      "createdAt": "2025-01-01T10:00:00Z",
      "updatedAt": "2025-01-01T10:05:00Z"
    }
  ],
  "page": 0,
  "size": 20,
  "totalElements": 1
}
```

#### `GET /integration/sagas/{sagaId}`

```
Response 200 OK:
{
  "sagaId": "uuid",
  "sagaType": "REPOSICION_INVENTARIO",
  "state": "COMPENSADA",
  "currentStep": 2,
  "steps": [
    {
      "stepName": "ENVIAR_A_PROVEEDOR",
      "status": "COMPENSADO",
      "executedAt": "2025-01-01T10:01:00Z"
    },
    {
      "stepName": "REGISTRAR_ENTRADA",
      "status": "FALLIDO",
      "executedAt": "2025-01-01T10:02:00Z"
    }
  ],
  "createdAt": "2025-01-01T10:00:00Z",
  "updatedAt": "2025-01-01T10:03:00Z"
}

Response 404 Not Found:
{
  "error": "SAGA_NO_ENCONTRADA",
  "sagaId": "uuid"
}
```

#### `POST /internal/notifications`

```
Request (desde alert-service via WebClient, DNS interno K3s):
{
  "alertaId": "uuid",
  "canal": "EMAIL",
  "contenido": {
    "destinatario": "admin@empresa.com",
    "asunto": "Alerta de bajo stock: Producto X",
    "cuerpo": "El stock de Producto X ha caído por debajo del mínimo configurado."
  }
}

Response 202 Accepted:
{
  "dispatchId": "uuid",
  "estado": "PENDIENTE",
  "canal": "EMAIL",
  "intentos": 0
}

Response 409 Conflict (notificación para misma alerta ya ENVIADA):
{
  "error": "NOTIFICACION_YA_ENVIADA",
  "alertaId": "uuid",
  "dispatchId": "uuid"
}
```

### Manejo de errores HTTP

| Excepción de dominio | HTTP Status | Código de error |
|---------------------|-------------|----------------|
| `SagaNoEncontradaException` | 404 | `SAGA_NO_ENCONTRADA` |
| `SagaTransicionInvalidaException` | 409 | `TRANSICION_SAGA_INVALIDA` |
| `ProveedorNoConfiguradoException` | 400 | `PROVEEDOR_NO_CONFIGURADO` |
| `NotificacionYaEnviadaException` | 409 | `NOTIFICACION_YA_ENVIADA` |
| `CircuitBreakerOpenException` | 503 | `SERVICIO_EXTERNO_NO_DISPONIBLE` |
| `CalloutTimeoutException` | 504 | `TIMEOUT_SERVICIO_EXTERNO` |
| `IllegalArgumentException` | 400 | `DATOS_INVALIDOS` |

---

## Especificación TDD por Capa (Red-Green-Refactor)

### Regla de oro: Camel + WireMock + StepVerifier

Los tests de rutas Camel usan **`camel-test-spring-junit5`** (anotación `@CamelSpringBootTest`) con **WireMock** para simular sistemas externos. Las aserciones de tipos reactivos usan siempre **`StepVerifier`** de `reactor-test`. Nunca `block()` ni `get()` en tests.

### Tests de Dominio

| Clase | Método | Escenario | Resultado esperado |
|-------|--------|-----------|-------------------|
| `SagaInstanceTest` | `avanzarPaso_debeIncrementarStepYCambiarEstado` | Saga en INICIADA | state = EN_PROCESO, currentStep = 1 |
| `SagaInstanceTest` | `avanzarPaso_fallaEnSagaCompletada` | Saga en COMPLETADA | Lanza `SagaTransicionInvalidaException` |
| `SagaInstanceTest` | `completar_debeTransicionarACompletada` | Saga en EN_PROCESO | state = COMPLETADA |
| `SagaInstanceTest` | `completarCompensacion_requiereEstadoCompensando` | Saga en EN_PROCESO | Lanza `SagaTransicionInvalidaException` |
| `NotificationDispatchTest` | `registrarIntento_exitoso_cambiaaEnviado` | dispatch PENDIENTE, exitoso=true | estado = ENVIADO, intentos = 1 |
| `NotificationDispatchTest` | `registrarIntento_fallido_cambiaaFallido` | dispatch PENDIENTE, exitoso=false | estado = FALLIDO, intentos = 1 |
| `NotificationDispatchTest` | `registrarIntento_fallaEnYaEnviado` | dispatch ENVIADO | Lanza `NotificacionYaEnviadaException` |
| `IntegrationLogTest` | `registrar_creaLogConTimestamp` | Parámetros válidos | createdAt no nulo, estado correcto |

### Tests de Aplicación (mocks de puertos)

| Clase | Método | Escenario | Mock | Resultado esperado |
|-------|--------|-----------|------|-------------------|
| `EnviarNotificacionUseCaseTest` | `ejecutar_exito` | Gateway retorna éxito | `notificacionGateway.enviar()` → `Mono.just(exitoso)` | dispatch ENVIADO, IntegrationLog EXITO guardado |
| `EnviarNotificacionUseCaseTest` | `ejecutar_gatewayFalla` | Gateway retorna error | `notificacionGateway.enviar()` → `Mono.error(RuntimeException)` | dispatch FALLIDO, IntegrationLog FALLIDO guardado |
| `EnviarNotificacionUseCaseTest` | `ejecutar_timeout` | Gateway lanza timeout | `notificacionGateway.enviar()` → `Mono.error(CalloutTimeoutException)` | IntegrationLog estado = TIMEOUT |
| `IniciarReposicionUseCaseTest` | `ejecutar_iniciarSaga_exitoso` | SagaCoordinator acepta | `sagaCoordinator.iniciarSaga()` → `Mono.just(saga)` | SagaInstance retornada en estado EN_PROCESO |
| `IniciarReposicionUseCaseTest` | `ejecutar_proveedorNoConfigurado` | Gateway rechaza proveedor | `sagaCoordinator.iniciarSaga()` → `Mono.error(ProveedorNoConfiguradoException)` | Error propagado sin swallow |
| `MonitorearSagaUseCaseTest` | `obtenerSaga_encontrada` | Repositorio retorna saga | `sagaInstanceRepository.findById()` → `Mono.just(saga)` | Saga retornada con steps |
| `MonitorearSagaUseCaseTest` | `obtenerSaga_noEncontrada` | Repositorio vacio | `sagaInstanceRepository.findById()` → `Mono.empty()` | Lanza `SagaNoEncontradaException` |
| `SagaOrchestratorUseCaseTest` | `ejecutarPaso_exito` | Paso completa OK | `sagaCoordinator.ejecutarPaso()` → `Mono.just(saga)` | saga retornada |
| `SagaOrchestratorUseCaseTest` | `ejecutarPaso_fallaDispara_compensacion` | Paso falla | `sagaCoordinator.ejecutarPaso()` → `Mono.error(SagaStepFallidoException)` | `sagaCoordinator.compensar()` llamado una vez |

```java
// Ejemplo test aplicación con StepVerifier
@ExtendWith(MockitoExtension.class)
class EnviarNotificacionUseCaseTest {

    @Mock NotificacionGateway notificacionGateway;
    @Mock NotificationDispatchRepository dispatchRepository;
    @Mock IntegrationLogRepository integrationLogRepository;
    @InjectMocks EnviarNotificacionUseCase useCase;

    @Test
    void ejecutar_exito_debeMarcarDispatchEnviado() {
        var command = new EnviarNotificacionCommand(
            UUID.randomUUID(), CanalNotificacion.EMAIL,
            Map.of("destinatario", "test@test.com", "cuerpo", "Alerta")
        );
        var dispatch = NotificationDispatch.crear(
            command.alertaId(), command.canal(), command.contenido());
        var result = NotificacionResult.exitoso();

        when(dispatchRepository.save(any())).thenReturn(Mono.just(dispatch));
        when(notificacionGateway.enviar(any())).thenReturn(Mono.just(result));
        when(integrationLogRepository.save(any()))
            .thenReturn(Mono.just(IntegrationLog.registrar(
                "NOTIFICACION", null, Map.of(), Map.of(), EstadoIntegracion.EXITO)));
        when(dispatchRepository.update(any())).thenReturn(Mono.just(dispatch));

        StepVerifier.create(useCase.ejecutar(command))
            .assertNext(d -> {
                assertThat(d.getEstado()).isEqualTo(EstadoDespacho.ENVIADO);
                assertThat(d.getIntentos()).isEqualTo(1);
            })
            .verifyComplete();
    }
}
```

### Tests de Infraestructura — Rutas Camel con WireMock

```java
// Ejemplo: NotificationRouteTest
@CamelSpringBootTest
@SpringBootTest
@WireMockTest(httpPort = 9090)   // WireMock en puerto fijo para tests
class NotificationRouteTest {

    @Autowired ProducerTemplate producerTemplate;

    @Test
    void notificationRoute_exito_retornaResultadoExitoso(
            WireMockRuntimeInfo wireMock) throws Exception {

        // Arrange — WireMock stub: POST 200 OK
        wireMock.getWireMock().register(
            post(urlEqualTo("/api/notificaciones"))
                .willReturn(aResponse()
                    .withStatus(200)
                    .withHeader("Content-Type", "application/json")
                    .withBody("{\"status\":\"OK\",\"messageId\":\"msg-123\"}")));

        var request = new NotificacionRequest(
            new NotificationDispatchId(UUID.randomUUID()),
            UUID.randomUUID(), CanalNotificacion.EMAIL,
            Map.of("destinatario", "test@test.com"));

        // Act — camel-reactive-streams: asyncRequestBody retorna Publisher
        Mono<NotificacionResult> result = Mono.fromCompletionStage(
            producerTemplate.asyncRequestBody(
                "direct:send-notification", request, NotificacionResult.class));

        // Assert — StepVerifier, NUNCA block()
        StepVerifier.create(result)
            .assertNext(r -> {
                assertThat(r.exitoso()).isTrue();
                assertThat(r.getMessageId()).isEqualTo("msg-123");
            })
            .verifyComplete();

        // Verificar que WireMock recibió exactamente 1 llamada
        wireMock.getWireMock().verifyThat(1,
            postRequestedFor(urlEqualTo("/api/notificaciones"))
                .withHeader("X-API-Key", matching(".+")));
    }

    @Test
    void notificationRoute_http503_circuitBreakerFallback_retornaFallido(
            WireMockRuntimeInfo wireMock) throws Exception {

        // Arrange — WireMock stub: POST 503 Service Unavailable
        wireMock.getWireMock().register(
            post(urlEqualTo("/api/notificaciones"))
                .willReturn(aResponse().withStatus(503)));

        var request = new NotificacionRequest(
            new NotificationDispatchId(UUID.randomUUID()),
            UUID.randomUUID(), CanalNotificacion.EMAIL,
            Map.of("destinatario", "test@test.com"));

        Mono<NotificacionResult> result = Mono.fromCompletionStage(
            producerTemplate.asyncRequestBody(
                "direct:send-notification", request, NotificacionResult.class));

        // El fallback del CB debe retornar NotificacionResult.fallido()
        StepVerifier.create(result)
            .assertNext(r -> {
                assertThat(r.exitoso()).isFalse();
                assertThat(r.getEstadoIntegracion())
                    .isEqualTo(EstadoIntegracion.FALLIDO);
            })
            .verifyComplete();

        // Verificar: se hicieron 4 intentos (1 inicial + 3 reintentos)
        wireMock.getWireMock().verifyThat(
            moreThanOrExactly(4),
            postRequestedFor(urlEqualTo("/api/notificaciones")));
    }

    @Test
    void notificationRoute_timeout_circuitBreakerAbre(
            WireMockRuntimeInfo wireMock) throws Exception {

        // Arrange — WireMock stub: delay mayor al timeout configurado (10s)
        wireMock.getWireMock().register(
            post(urlEqualTo("/api/notificaciones"))
                .willReturn(aResponse()
                    .withStatus(200)
                    .withFixedDelay(12000)));  // 12s > 10s timeout

        var request = new NotificacionRequest(
            new NotificationDispatchId(UUID.randomUUID()),
            UUID.randomUUID(), CanalNotificacion.EMAIL,
            Map.of("destinatario", "test@test.com"));

        Mono<NotificacionResult> result = Mono.fromCompletionStage(
            producerTemplate.asyncRequestBody(
                "direct:send-notification", request, NotificacionResult.class));

        // Timeout activa fallback con TIMEOUT state
        StepVerifier.create(result)
            .assertNext(r -> {
                assertThat(r.exitoso()).isFalse();
                assertThat(r.getEstadoIntegracion())
                    .isEqualTo(EstadoIntegracion.TIMEOUT);
            })
            .verifyComplete();

        // Enviar suficientes llamadas fallidas para abrir el CB
        // (10 llamadas con >50% fallo → CB pasa a OPEN)
        // En el segundo test, verificar que el CB está OPEN:
        // la ruta retorna fallback inmediatamente sin llamar a WireMock
    }
}
```

### Tests de Infraestructura — Saga con WireMock

| Clase | Método | Escenario | WireMock Mock | Resultado esperado |
|-------|--------|-----------|--------------|-------------------|
| `SagaReposicionRouteTest` | `saga_happy_path` | Steps 1 y 2 exitosos | Proveedor REST → 200, inventory-service → 201 | SagaInstance COMPLETADA; saga_step_log tiene 2 entries COMPLETADO |
| `SagaReposicionRouteTest` | `saga_step2_falla_compensaStep1` | Step 1 OK, Step 2 falla | Proveedor → 200, inventory-service → 500 | SagaInstance COMPENSADA; compensar-envio-proveedor llamado 1 vez; SolicitudReposicionFallida en outbox |
| `SagaReposicionRouteTest` | `saga_compensacion_idempotente` | Compensación llamada 2 veces | Proveedor → 200 en ambas llamadas | Segunda compensación es no-op; processed_message tabla previene duplicado |
| `SagaAjusteRouteTest` | `saga02_happy_path` | AjusteAprobado consumido, stock aplicado OK | inventory-service → 200 | SagaInstance COMPLETADA |
| `SagaAjusteRouteTest` | `saga02_step3_falla_compensaSteps2y1` | Step 3 falla (inventory error) | inventory-service → 500 | compensar-ajuste-aprobado llamado; compensar-adjustment llamado en orden inverso |

```java
// Ejemplo: test saga con fallo y compensación
@CamelSpringBootTest
@SpringBootTest
@WireMockTest(httpPort = 9090)
class SagaReposicionRouteTest {

    @Autowired ProducerTemplate producerTemplate;
    @Autowired SagaInstanceRepository sagaInstanceRepository;
    @Autowired SagaStepLogRepository sagaStepLogRepository;

    @Test
    void saga_step2_falla_debeCompensarStep1(
            WireMockRuntimeInfo wireMock) {

        // Arrange
        UUID proveedorId = UUID.randomUUID();
        UUID productoId  = UUID.randomUUID();

        // Step 1: proveedor acepta
        wireMock.getWireMock().register(
            post(urlMatching("/api/proveedores/.*/ordenes"))
                .willReturn(aResponse().withStatus(200)
                    .withBody("{\"ordenId\":\"ord-001\"}")));

        // Step 2: inventory-service falla (simula 500)
        wireMock.getWireMock().register(
            post(urlEqualTo("/internal/inventory/movements"))
                .willReturn(aResponse().withStatus(500)));

        // Compensación Step 1: cancelar orden proveedor
        wireMock.getWireMock().register(
            post(urlMatching("/api/proveedores/.*/ordenes/.*/cancelar"))
                .willReturn(aResponse().withStatus(200)));

        Map<String, Object> payload = Map.of(
            "productoId", productoId.toString(),
            "cantidad", "100",
            "proveedorId", proveedorId.toString(),
            "tipoConexion", "REST"
        );

        SagaInstance sagaInstance = SagaInstance.iniciar(
            SagaType.REPOSICION_INVENTARIO, payload);

        // Act
        Mono<SagaInstance> resultado = Mono.fromCompletionStage(
            producerTemplate.asyncSendBodyAndHeaders(
                "direct:saga-reposicion",
                payload,
                Map.of("sagaId", sagaInstance.getSagaId().value().toString())
            )
        ).flatMap(r -> sagaInstanceRepository.findById(sagaInstance.getSagaId()));

        // Assert
        StepVerifier.create(resultado)
            .assertNext(saga -> {
                assertThat(saga.getState()).isEqualTo(SagaState.COMPENSADA);
            })
            .verifyComplete();

        // Verificar que el proveedor fue llamado (Step 1) Y la compensación fue llamada
        wireMock.getWireMock().verifyThat(1,
            postRequestedFor(urlMatching("/api/proveedores/.*/ordenes")));
        wireMock.getWireMock().verifyThat(1,
            postRequestedFor(urlMatching("/api/proveedores/.*/ordenes/.*/cancelar")));

        // Verificar saga_step_log: Step 1 COMPENSADO, Step 2 FALLIDO
        StepVerifier.create(
            sagaStepLogRepository.findBySagaId(sagaInstance.getSagaId()))
            .assertNext(log -> {
                assertThat(log.getStatus())
                    .isIn(SagaStepStatus.FALLIDO, SagaStepStatus.COMPENSADO);
            })
            .expectNextCount(1)
            .verifyComplete();
    }
}
```

### Tests de Infraestructura — R2DBC con Testcontainers

| Clase | Método | Escenario | Resultado esperado |
|-------|--------|-----------|-------------------|
| `SagaInstanceR2dbcAdapterTest` | `save_findById` | Persistir y recuperar saga | Saga recuperada igual a la guardada |
| `SagaInstanceR2dbcAdapterTest` | `findByTypeAndState` | Filtrar por tipo y estado | Solo sagas del tipo/estado solicitado |
| `NotificationDispatchR2dbcTest` | `save_update_intentos` | Guardar dispatch, registrar intento | intentos = 1, estado = ENVIADO |
| `IntegrationLogR2dbcTest` | `save_findByProveedorId` | Log de integración por proveedor | Log recuperado con payload correcto |
| `OutboxRelayTest` | `relay_publicaAKafka_yMarcaPublished` | Mensajes PENDING en outbox | Publicados en Kafka, estado = PUBLISHED |

### Umbrales de cobertura de código

| Capa | Cobertura mínima | Justificación |
|------|-----------------|---------------|
| Dominio (entidades, VOs, excepciones) | ≥ 85% | Lógica de negocio crítica: transiciones de saga, invariantes |
| Aplicación (use cases, commands) | ≥ 80% | Lógica de orquestación con mocks de puertos |
| Infraestructura Camel (rutas) | ≥ 75% | Alta complejidad ciclomática en rutas EIP; branches de CB y retry |
| Infraestructura R2DBC (adapters) | ≥ 75% | Tests Testcontainers cubren caminos principales |
| API REST (controllers) | ≥ 80% | `@WebFluxTest` cubre todos los endpoints y errores |

---

## Criterios de Aceptación

### CA-1: Rutas Camel compiladas y activas

```bash
# Las rutas deben aparecer en el registro de Camel al arrancar
kubectl logs -n apps deploy/integration-service | grep "Route: .* started"
# Salida esperada (5 rutas):
# Route: notification-route started
# Route: reposicion-rest-route started
# Route: reposicion-ftp-route started
# Route: saga-reposicion-route started
# Route: saga-ajuste-monitor-route started
```

### CA-2: Saga-01 happy path completa

```bash
TOKEN=$(curl -s -X POST \
  "http://<VPS_IP>:8180/realms/controlstock/protocol/openid-connect/token" \
  -d "client_id=test-client&grant_type=password&username=operador@test.com&password=test" \
  | jq -r '.access_token')

# Iniciar Saga-01
SAGA=$(curl -s -X POST "http://<VPS_IP>:30089/integration/reposiciones" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "productoId": "'"$PRODUCTO_ID"'",
    "cantidad": 50,
    "proveedorId": "'"$PROVEEDOR_ID"'",
    "tipoConexion": "REST"
  }')
echo $SAGA | jq '.'
# Debe contener: "state": "EN_PROCESO", sagaId presente

SAGA_ID=$(echo $SAGA | jq -r '.sagaId')

# Esperar a que la saga complete (máx 30s en dev con WireMock)
sleep 10

# Verificar estado final
curl -s "http://<VPS_IP>:30089/integration/sagas/$SAGA_ID" \
  -H "Authorization: Bearer $TOKEN" | jq '.state'
# Salida esperada: "COMPLETADA"

# Verificar saga_step_log tiene 2-3 pasos COMPLETADO
curl -s "http://<VPS_IP>:30089/integration/sagas/$SAGA_ID" \
  -H "Authorization: Bearer $TOKEN" | jq '.steps[] | .status'
# Salida esperada: "COMPLETADO" x2-3
```

### CA-3: Saga-01 con fallo en Step 2 ejecuta compensaciones en orden inverso

```bash
# Configurar WireMock para que inventory-service falle (Step 2)
curl -s -X POST "http://<VPS_IP>:30099/__admin/mappings" \
  -H "Content-Type: application/json" \
  -d '{
    "request": {"method": "POST", "url": "/internal/inventory/movements"},
    "response": {"status": 500, "body": "{\"error\":\"Internal Error\"}"}
  }'

# Iniciar Saga-01
SAGA=$(curl -s -X POST "http://<VPS_IP>:30089/integration/reposiciones" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"productoId":"'"$PRODUCTO_ID"'","cantidad":50,"proveedorId":"'"$PROVEEDOR_ID"'","tipoConexion":"REST"}')
SAGA_ID=$(echo $SAGA | jq -r '.sagaId')

sleep 15

# La saga debe estar COMPENSADA (no COMPLETADA)
STATE=$(curl -s "http://<VPS_IP>:30089/integration/sagas/$SAGA_ID" \
  -H "Authorization: Bearer $TOKEN" | jq -r '.state')
echo "Estado saga: $STATE"  # Esperado: COMPENSADA

# Verificar que Step 1 fue compensado (orden inverso)
STEPS=$(curl -s "http://<VPS_IP>:30089/integration/sagas/$SAGA_ID" \
  -H "Authorization: Bearer $TOKEN" | jq '.steps')
echo $STEPS | jq '.[] | select(.stepName == "ENVIAR_A_PROVEEDOR") | .status'
# Esperado: COMPENSADO

echo $STEPS | jq '.[] | select(.stepName == "REGISTRAR_ENTRADA") | .status'
# Esperado: FALLIDO

# Verificar que el outbox contiene SolicitudReposicionFallida
kubectl exec -n databases deploy/postgresql -- psql \
  -U controlstock_integration -d controlstock_integration \
  -c "SELECT event_type, estado FROM outbox ORDER BY created_at DESC LIMIT 1;"
# Esperado: SolicitudReposicionFallida | PENDING o PUBLISHED
```

### CA-4: Resilience4j Circuit Breaker abre y se recupera

```bash
# Configurar WireMock para que el servicio de notificaciones siempre falle
curl -s -X POST "http://<VPS_IP>:30099/__admin/mappings" \
  -H "Content-Type: application/json" \
  -d '{"request":{"method":"POST","url":"/api/notificaciones"},"response":{"status":503}}'

# Enviar 15 notificaciones (más del umbral del sliding window de 10)
for i in $(seq 1 15); do
  curl -s -X POST "http://<VPS_IP>:30089/internal/notifications" \
    -H "Content-Type: application/json" \
    -d '{"alertaId":"'"$(uuidgen)"'","canal":"EMAIL","contenido":{"destinatario":"t@t.com"}}'
done

# Verificar que el CB está OPEN (sin llamar a WireMock)
kubectl logs -n apps deploy/integration-service | grep "CircuitBreaker.*OPEN"
# Debe aparecer el log de apertura del CB

# Verificar en notification_dispatch que todos los intentos están en FALLIDO
kubectl exec -n databases deploy/postgresql -- psql \
  -U controlstock_integration -d controlstock_integration \
  -c "SELECT estado, COUNT(*) FROM notification_dispatch GROUP BY estado;"
# Esperado: FALLIDO | 15

# Restaurar WireMock a responder 200
curl -s -X DELETE "http://<VPS_IP>:30099/__admin/mappings"
curl -s -X POST "http://<VPS_IP>:30099/__admin/mappings" \
  -H "Content-Type: application/json" \
  -d '{"request":{"method":"POST","url":"/api/notificaciones"},"response":{"status":200,"body":"{\"status\":\"OK\"}"}}'

# Esperar a que el CB pase a HALF_OPEN (30s de wait)
# Enviar nueva notificación — debe tener éxito y cerrar el CB
sleep 35
curl -s -X POST "http://<VPS_IP>:30089/internal/notifications" \
  -H "Content-Type: application/json" \
  -d '{"alertaId":"'"$(uuidgen)"'","canal":"EMAIL","contenido":{"destinatario":"t@t.com"}}'

kubectl logs -n apps deploy/integration-service | grep "CircuitBreaker.*CLOSED"
```

### CA-5: `notification_dispatch.intentos` rastreado correctamente

```bash
# Enviar notificación con WireMock fallando 2 veces y luego exitoso
# (Resilience4j retry: intentos = 3 antes de éxito)
# Verificar que notification_dispatch.intentos refleja el conteo real

kubectl exec -n databases deploy/postgresql -- psql \
  -U controlstock_integration -d controlstock_integration \
  -c "SELECT alerta_id, canal, estado, intentos, ultimo_intento
      FROM notification_dispatch
      ORDER BY created_at DESC LIMIT 5;"
# Cada fila debe mostrar el número correcto de intentos (≥ 1 para fallidos, 1-4 para enviados con retry)
```

### CA-6: Idempotencia de compensaciones

```bash
# Llamar a la compensación de un saga step dos veces con el mismo sagaId
# La segunda llamada debe ser no-op (sin errores, sin duplicados en saga_step_log)

SAGA_ID="uuid-de-saga-ya-compensada"

# Primera compensación (ya ejecutada previamente)
curl -s -X POST "http://<VPS_IP>:30089/integration/sagas/$SAGA_ID/ejecutar" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"stepName": "COMPENSAR_ENVIO_PROVEEDOR"}'

# Segunda llamada idéntica
curl -s -X POST "http://<VPS_IP>:30089/integration/sagas/$SAGA_ID/ejecutar" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"stepName": "COMPENSAR_ENVIO_PROVEEDOR"}'

# Verificar: processed_message previene duplicado
kubectl exec -n databases deploy/postgresql -- psql \
  -U controlstock_integration -d controlstock_integration \
  -c "SELECT COUNT(*) FROM saga_step_log
      WHERE saga_id = '$SAGA_ID'
      AND step_name = 'COMPENSAR_ENVIO_PROVEEDOR'
      AND status = 'COMPENSADO';"
# Esperado: 1 (no 2 — la segunda llamada fue ignorada por idempotencia)
```

### CA-7: Credenciales de Vault cargadas correctamente

```bash
# Verificar que el servicio cargó credenciales desde Vault (no texto en application.yaml)
kubectl logs -n apps deploy/integration-service | grep "Vault"
# Esperado: "Fetched config from Vault" o similar de spring-cloud-vault

# Los endpoints de integración deben incluir el header X-API-Key en las llamadas a WireMock
kubectl exec -n apps deploy/wiremock -- \
  curl -s "http://localhost:8080/__admin/requests" | jq \
  '.requests[] | select(.request.url == "/api/notificaciones") | .request.headers["X-API-Key"]'
# El header debe estar presente (valor no vacío)
```

### CA-8: WireMock valida los 3 escenarios por ruta Camel

Los tests de integración deben verificar los 3 escenarios para **cada** ruta Camel que llama a sistemas externos:

| Ruta | Escenario 1 (éxito) | Escenario 2 (error HTTP) | Escenario 3 (timeout) |
|------|--------------------|--------------------------|-----------------------|
| `notification-route` | WireMock 200 OK | WireMock 503 | WireMock delay 12s > 10s timeout |
| `reposicion-rest-route` | WireMock 200 OK | WireMock 503 | WireMock delay 12s |
| `reposicion-ftp-route` | Archivo subido OK | FTP connection refused | FTP timeout (socket timeout) |

```bash
# Ejecutar suite de tests completa
mvn test -pl integration-service -Dtest="*RouteTest,*SagaTest"
# Debe pasar: NotificationRouteTest (3 tests), ReposicionRestRouteTest (3 tests),
#             ReposicionFtpRouteTest (3 tests), SagaReposicionRouteTest (4 tests),
#             SagaAjusteRouteTest (2 tests)

# Verificar cobertura por capa
mvn jacoco:report -pl integration-service
# domain: ≥ 85%, application: ≥ 80%, infrastructure: ≥ 75%
```

### CA-9: Health y observabilidad

```bash
# Health check readiness
curl -s "http://<VPS_IP>:30089/actuator/health/readiness" | jq '.status'
# Esperado: "UP"

# Verificar que las rutas Camel aparecen en health
curl -s "http://<VPS_IP>:30089/actuator/health" | jq '.components.camelRoute'
# Debe mostrar status UP para todas las rutas

# Métricas Camel en Prometheus
curl -s "http://<VPS_IP>:30089/actuator/prometheus" | grep "camel_route"
# Debe incluir métricas: camel_route_exchanges_total, camel_route_exchanges_failed_total

# Verificar trazas distribuidas en Jaeger (LRA + Camel)
curl -s "http://<VPS_IP>:16686/api/traces?service=integration-service&limit=5" \
  | jq '.data[0].spans | length'
# Debe mostrar spans para Camel routes + LRA coordinator
```
