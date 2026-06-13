# Software Design Document — Diseño Técnico

**Proyecto:** ControlStock | Parte del conjunto SDD Técnico — etapa Diseño Técnico del SDLC.
Documentos complementarios: `SDD-ControlStock-system.md` · `SDD-ControlStock-infrastructure.md`

---

## 1. Diseño de APIs

Especificación completa en formato OpenAPI 3.0.3: [SDD-ControlStock-openapi.yaml](api/SDD-ControlStock-openapi.yaml)

Todos los endpoints son validados por Kong API Gateway (JWT RS256, rate limiting 200 req/min) antes de ser enrutados a los microservicios. Los endpoints de compensación de saga (tag `Saga Compensation`) son invocados únicamente por el orquestador (`integration-service`) y son idempotentes.

### Resumen de Endpoints por Bounded Context

| Bounded Context | Método | Ruta | Descripción |
|---|---|---|---|
| Catalog | GET | `/catalog/categories` | Listar categorías |
| Catalog | POST | `/catalog/categories` | Crear categoría |
| Catalog | GET/PUT | `/catalog/categories/{id}` | Obtener / actualizar categoría |
| Catalog | GET | `/catalog/products` | Listar productos (filtros: categoría, estado) |
| Catalog | POST | `/catalog/products` | Crear producto |
| Catalog | GET/PUT/DELETE | `/catalog/products/{id}` | Obtener / actualizar / inactivar producto |
| Inventory | GET | `/inventory/stock` | Listar stock actual (filtros: categoría, bajominimo) |
| Inventory | GET | `/inventory/stock/{productId}` | Stock actual de un producto |
| Inventory | GET/POST | `/inventory/movements` | Listar / registrar movimiento (ENTRADA o SALIDA) |
| Inventory | GET | `/inventory/movements/{id}` | Detalle de movimiento |
| Inventory | POST | `/inventory/movements/{id}/anular` | Anular movimiento (permanece visible en Kardex) |
| Inventory | GET | `/inventory/kardex/{productId}` | Kardex cronológico con saldo acumulado |
| Adjustment | GET/POST | `/adjustments` | Listar / crear solicitud de ajuste |
| Adjustment | GET | `/adjustments/{id}` | Detalle de ajuste |
| Adjustment | POST | `/adjustments/{id}/aprobar` | Aprobar ajuste (rol Supervisor/Admin) |
| Adjustment | POST | `/adjustments/{id}/rechazar` | Rechazar ajuste (rol Supervisor/Admin) |
| Alert | GET | `/alerts` | Listar alertas (filtros: tipo, estado, producto) |
| Alert | POST | `/alerts/{id}/reconocer` | Reconocer alerta activa |
| Supplier | GET/POST | `/suppliers` | Listar / registrar proveedor |
| Supplier | GET/PUT/DELETE | `/suppliers/{id}` | Obtener / actualizar / inactivar proveedor |
| Reporting | GET/POST | `/reports` | Listar / solicitar generación de reporte |
| Reporting | GET | `/reports/{id}` | Estado de solicitud de reporte |
| Reporting | GET | `/reports/{id}/download` | Descargar archivo de reporte generado |
| Audit | GET | `/audit` | Consultar log de auditoría (rol Auditor/Admin) |
| Integration | POST | `/integration/reposiciones` | Iniciar reposición a proveedor (Saga-01) |
| Integration | GET | `/integration/sagas` | Listar instancias de saga |
| Integration | GET | `/integration/sagas/{sagaId}` | Consultar estado de saga |
| Saga Compensation | POST | `/inventory/movements/{id}/compensar` | Revertir entrada (Saga-01) — idempotente |
| Saga Compensation | POST | `/adjustments/{id}/compensar` | Revertir ajuste aprobado (Saga-02) — idempotente |
| Integration (interno) | POST | `/integration/sagas/{sagaId}/ejecutar` | Ejecutar/retomar paso de saga (API interna del orquestador) |

---

## 2. Diseño de Persistencia

### Estrategia General

**Patrón Database-per-Service:** cada microservicio es propietario exclusivo de su base de datos. Ningún servicio accede directamente a la BD de otro (ni lectura ni escritura). La comunicación de datos entre servicios ocurre exclusivamente mediante eventos Kafka o consultas REST al servicio propietario.

**Provisioning:** las BDs son creadas automáticamente por `init-databases.sh` al ejecutar `base-infrastructure-builder.sh`. La convención de nombre es `controlstock_<svc_slug>` (prefijo `controlstock`, slug del servicio en snake_case).

**Migraciones:** cada servicio aplica su esquema inicial mediante **Liquibase standalone** (`run-liquibase-migrations.sh --gitea-clone`). Los changelogs residen en el repo `controlstock-migrations` en Gitea (`http://VPS_IP:3000/controlstock/controlstock-migrations`). No se usa Flyway (incompatible con R2DBC reactivo).

**Consistencia de eventos:** el read model MongoDB tiene consistencia eventual respecto al command side PostgreSQL. El lag es proporcional al throughput de Kafka (< 1 s en operación normal).

### Modelo de Datos

Modelo relacional (PostgreSQL): [SDD-ControlStock-schema.sql](database/SDD-ControlStock-schema.sql)

Modelo documental (MongoDB read model): [SDD-ControlStock-collections.js](database/SDD-ControlStock-collections.js)

### Resumen por Bounded Context

| Bounded Context | BD propietaria | Motor | Tablas / Colecciones principales |
|---|---|---|---|
| IAM (BC-01) | `controlstock_iam` | PostgreSQL 16 | usuarios, roles, permisos, rol_permisos, usuario_roles |
| Catalog (BC-02) | `controlstock_catalog` | PostgreSQL 16 | categorias, productos, outbox |
| Inventory (BC-03) | `controlstock_inventory` | PostgreSQL 16 | stock_levels, inventory_movements, outbox, processed_message |
| Inventory (BC-03) | `controlstock_readmodel` | MongoDB 7 | kardex, movimientos, stock |
| Adjustment (BC-04) | `controlstock_adjustment` | PostgreSQL 16 | adjustment_requests, adjustment_decisions, outbox, processed_message |
| Alert (BC-05) | `controlstock_alert` | PostgreSQL 16 | alert_rules, alert_events |
| Supplier (BC-06) | `controlstock_supplier` | PostgreSQL 16 | suppliers, integration_configs |
| Supplier (BC-06) | `controlstock_readmodel` | MongoDB 7 | proveedores |
| Reporting (BC-07) | `controlstock_reporting` | PostgreSQL 16 | report_schema_catalog, report_requests, report_files |
| Reporting (BC-07) | MinIO bucket `controlstock-reports` | S3-compatible | .parquet, XLSX, CSV, PDF |
| Audit (BC-08) | `controlstock_audit` | PostgreSQL 16 | audit_log (append-only) |
| Integration (BC-09) | `controlstock_integration` | PostgreSQL 16 | integration_logs, notification_dispatch, saga_instance, saga_step_log, outbox, processed_message |
| Catalog (BC-02) | `controlstock_readmodel` | MongoDB 7 | productos |

### Layout de Almacenamiento de Objetos (MinIO / OCI Object Storage)

```
controlstock-reports/
├── parquet/
│   └── {report_type}/{year}/{month}/{report_request_id}.parquet
└── output/
    ├── xlsx/{report_request_id}.xlsx
    ├── csv/{report_request_id}.csv
    └── pdf/{report_request_id}.pdf
```

---

## 3. Flujos Técnicos Principales

### Flujo: Registro de Entrada de Inventario

1. **Kong:** valida JWT RS256; aplica RBAC (permiso `inventory:write`); enruta a `inventory-service`.
2. **inventory-service:** `POST /inventory/movements` con tipo ENTRADA.
3. **inventory-service — Dominio:** valida producto activo y cantidad > 0; actualiza `StockLevel` de forma atómica; crea `InventoryMovement` (saldo_resultante = stock_previo + cantidad).
4. **inventory-service — Outbox:** escribe eventos `EntradaRegistrada` y `StockActualizado` en tabla `outbox` dentro de la misma transacción R2DBC.
5. **inventory-service — Outbox Relay (scheduled):** lee `outbox` con status='PENDING'; publica en Kafka topics `inventory.entradas` y `inventory.stock-actualizado`; actualiza status='PUBLISHED'.
6. **inventory-service — Projection Consumer:** consume `EntradaRegistrada`; actualiza colecciones `kardex`, `movimientos`, `stock` en MongoDB `controlstock_readmodel`.
7. **alert-service:** consume `StockActualizado`; evalúa `stock_actual ≥ stock_máximo`; si cumple: crea `AlertEvent` (SOBRESTOCK) en `controlstock_alert`; llama `POST /integration/notifications` en `integration-service` vía REST interno.
8. **audit-service:** consume `EntradaRegistrada`; persiste `AuditRecord` append-only en `controlstock_audit`.
9. **integration-service (si hay notificación):** ruta Camel `http` llama al servicio de notificaciones externo; registra resultado en `notification_dispatch`.

---

### Flujo: Registro de Salida de Inventario

1. **Kong → inventory-service:** validación y enrutamiento idénticos a entrada.
2. **inventory-service — Dominio:** verifica `cantidad_solicitada ≤ stock_actual`; si no, responde HTTP 409 con stock disponible. Si pasa: actualiza `StockLevel` (reducción atómica); crea `InventoryMovement` (SALIDA).
3. **Pasos 4-9:** idénticos al flujo de entrada; evaluación de `AlertaBajoStock` en lugar de Sobrestock.

---

### Flujo: Aprobación de Ajuste de Inventario (Saga-02)

**Estilo:** Orquestación (orquestador en `integration-service`, Camel Saga EIP + Narayana LRA).

| # | Paso | Servicio | Evento/Comando | Compensación | Idempotencia |
|---|---|---|---|---|---|
| 1 | Crear AdjustmentRequest en estado PENDIENTE | adjustment-service | `AjusteSolicitado` (DE-007) | — | — |
| 2 | Supervisor aprueba; registrar AdjustmentDecision | adjustment-service | `AjusteAprobado` (DE-008) | `AjusteRevertido` (DE-010) | saga_id en adjustment_request |
| 3 | Aplicar impacto en stock; crear KardexRecord | inventory-service | `StockActualizado` (DE-006) | `POST /inventory/movements/{id}/compensar` | processed_message (message_id = saga_id + step) |

**Ante fallo en paso 3:** el orquestador dispara `POST /adjustments/{id}/compensar` en adjustment-service (idempotente via `processed_message`); `AdjustmentRequest` transiciona a estado ERROR; se registra `AuditRecord` de compensación; stock no refleja el ajuste fallido.

**Transactional Outbox:** `adjustment-service` e `inventory-service` escriben sus eventos de dominio en sus tablas `outbox` locales dentro de la misma transacción de negocio; el relay scheduled los publica en Kafka.

---

### Saga-01: Reposición de Inventario vía Proveedor Externo

**Estilo:** Orquestación (orquestador en `integration-service`, Camel Saga EIP + Narayana LRA).

| # | Paso | Servicio | Evento/Comando | Compensación | Idempotencia |
|---|---|---|---|---|---|
| 1 | Enviar SolicitudReposicion al proveedor externo | integration-service (Camel `http`/`file`) | `SolicitudReposicionEnviada` (DE-016) | `SolicitudReposicionCancelada` | integration_log.id |
| 2 | Registrar EntradaRegistrada en Inventory por cantidad confirmada | inventory-service | `EntradaRegistrada` (DE-004) | `POST /inventory/movements/{id}/compensar` → `EntradaRevertida` (DE-019) | processed_message (message_id = saga_id + step) |
| 3 | Evaluar alertas de stock resultante (informativo) | alert-service | — | — | — |

**Ante fallo en paso 1 o 2:** el orquestador emite `EntradaRevertida` (si paso 2 fue parcialmente ejecutado); registra `SolicitudReposicionFallida` (DE-018); resultado en `integration_logs`; stock no queda en estado inconsistente.

---

### Flujo: Generación de Alerta y Notificación

1. **inventory-service:** publica `StockActualizado` (DE-006) vía Outbox → Kafka.
2. **alert-service:** consume `StockActualizado`; compara `stock_actual` vs. `alert_rules` del producto.
3. Si `stock_actual ≤ stock_mínimo`: genera `AlertaBajoStock` (DE-012); crea `AlertEvent` en `controlstock_alert`.
4. Si `stock_actual ≥ stock_máximo`: genera `AlertaSobrestock` (DE-013); crea `AlertEvent`.
5. **alert-service → integration-service:** `POST /internal/notifications` (REST interno K3s, no pasa por Kong).
6. **integration-service:** ruta Camel ejecuta llamada al proveedor externo de notificaciones con Resilience4j (reintentos backoff exponencial, circuit breaker). Registra resultado en `notification_dispatch`.
7. Si fallo: `NotificacionFallida` (DE-015) registrado; `AlertEvent` permanece ACTIVA y visible en dashboard.

---

### Flujo ETL: Generación de Reporte (On-demand)

1. **report-service:** recibe `POST /reports`; crea `ReportRequest` en estado SOLICITADO en `controlstock_reporting`.
2. **report-service:** publica evento de solicitud en Kafka (topic `reporting.requests`).
3. **report-etl-service** (Spark job disparado por Kafka consumer):
   a. Lee `report_schema_catalog` desde `controlstock_reporting` (JDBC) para obtener esquema y reglas de integridad.
   b. Extrae datos del read model MongoDB via Spark MongoDB Connector (o de `controlstock_audit` via JDBC para el tipo `auditoria-operaciones`).
   c. Valida DataFrame contra el esquema del catálogo (Factory por `ReportType`).
   d. Genera archivo `.parquet` en MinIO `controlstock-reports/parquet/`.
   e. Publica `ReporteParquetGenerado` (DE-020) en Kafka con URL del .parquet y `formatoDestino`.
4. **report-format-consumer** (OpenFaaS, disparada por Kafka Connector):
   a. Lee .parquet desde MinIO.
   b. Genera XLSX/CSV/PDF según `formatoDestino`.
   c. Almacena archivo final en MinIO `controlstock-reports/output/`.
   d. Notifica a `report-service` con URL del archivo final.
5. **report-service:** actualiza `ReportRequest` a estado COMPLETADO; almacena URL en `report_files`.
6. **Usuario:** descarga el archivo via `GET /reports/{id}/download`.

Si el ETL falla: publica `ReporteETLFallido` (DE-021); `ReportRequest` transiciona a FALLIDO; `AuditRecord` registra el fallo; usuario puede reintentar.

---

### Flujo: Consumo de API Externa (ACL via integration-service)

Para cada sistema externo existe una ruta Camel dedicada en `integration-service`:

1. **Servicio de dominio** (ej. alert-service) invoca `integration-service` REST interno K3s.
2. **integration-service — Camel route:** aplica ACL del sistema externo (credenciales desde Vault via `spring-cloud-vault-config`); ejecuta llamada al sistema externo con Resilience4j (circuit breaker + retry con backoff exponencial); traduce la respuesta al modelo del dominio.
3. **integration-service:** registra resultado en `integration_logs`; responde al servicio invocante.

Prohibido: `block()` en el bridge reactivo Camel↔Reactor (`camel-reactive-streams` obligatorio).

---

## 4. Diseño de Seguridad Técnica

### Autenticación

- **Mecanismo:** OIDC/OAuth 2.0 via Keycloak realm `controlstock`. JWT firmado con RS256 (clave privada en Keycloak).
- **Validación:** Kong API Gateway valida la firma JWT via JWKS endpoint de Keycloak antes de enrutar cualquier petición. Los microservicios internos confían en los claims pre-validados del JWT.
- **Expiración:** configurable en Keycloak (recomendado: access token 15 min, refresh token 8 h).
- **Revocación:** inmediata en Keycloak; Kong invalida el token en la siguiente petición via TTL de caché de claves públicas (max-age 5 min).

### Autorización (RBAC)

- **Modelo:** RBAC granular por módulo y operación. Los claims del JWT incluyen los roles asignados al usuario en Keycloak.
- **Aplicación:** Kong aplica verificación de rol por ruta (`Kong RBAC plugin`). Los microservicios aplican verificación adicional en el nivel de caso de uso para operaciones sensibles (ej. `adjustment-service` verifica rol Supervisor/Admin en el endpoint de aprobación).
- **Acceso negado:** HTTP 403 sin datos del sistema en el body; el intento queda en `audit_log`.

### Gestión de Secretos

- **Motor:** HashiCorp Vault KV v2 (`controlstock/<env>/<svc>`). Namespace `secrets` en K3s.
- **Acceso en runtime:** `spring-cloud-vault-config`; AppRole authentication con TTL corto en leases.
- **Credenciales de proveedores:** almacenadas exclusivamente en Vault (`controlstock/<env>/integration-service/proveedor-{id}`). Referenciadas por `vault_secret_path` en `integration_configs`.
- **Rotación:** sin redeploy; los microservicios recargan secretos al renovar el lease de Vault.

### Cifrado y Transporte

- **Externo:** TLS obligatorio en todos los canales externos (Kong HTTPS, Traefik HTTPS, llamadas salientes de `integration-service`).
- **Kafka:** TLS en broker Strimzi con ACLs por topic: solo el servicio propietario puede producir en su topic; los consumidores autorizados tienen permiso de lectura.
- **PostgreSQL / MongoDB:** acceso restringido a la Zona de Aplicación (K3s network policy); credenciales desde Vault.
- **Vault:** acceso solo con AppRole authentication; audit log de Vault activo.

### Protección de APIs

- **Rate limiting:** 200 req/min global en Kong; configurable por ruta.
- **CORS:** gestionado en Kong; solo orígenes del frontend ControlStock permitidos en endpoints web.
- **API pública (RF-020):** tokens de API independientes (gestionados por Kong); permisos separados del RBAC interno.
- **Logs seguros:** Logback/MDC configurado para excluir campos sensibles (passwords, tokens, API keys). gitleaks en cada commit del pipeline CI.

### Auditoría de Seguridad

- Intentos de autenticación fallidos: registrados por Keycloak; opcionalmente consumidos por `audit-service`.
- Accesos denegados (HTTP 403): registrados por Kong y/o el microservicio receptor en `audit_log`.
- Operaciones sobre usuarios, roles y permisos: `AuditRecord` con JWT del Administrador.
- Compensaciones de saga (`AjusteRevertido`, `EntradaRevertida`): `AuditRecord` en `audit_log`.

---

## 5. Especificación de Pruebas (ATDD)

### Matriz de Trazabilidad AC → Prueba Técnica

| Criterio ATDD | Tipo de prueba | Componente bajo prueba | Escenarios técnicos clave | Gate de aceptación |
|---|---|---|---|---|
| AC-001-S1 | Integration | inventory-service (R2DBC PostgreSQL) | `POST /inventory/movements` (tipo=ENTRADA, cantidad=30, producto ACTIVO); verificar `stock_levels.stock_actual` = previo + 30; `inventory_movements` row creado; `outbox` row con status='PENDING' → 'PUBLISHED' | HTTP 201; `stock_levels.stock_actual` incrementado; `KardexEntry` en MongoDB colección `movimientos` |
| AC-001-S2 | Integration | inventory-service → alert-service (Kafka) | Producir `StockActualizado` con stock_actual ≥ stock_máximo; verificar `alert_events.tipo_alerta`='SOBRESTOCK' en `controlstock_alert`; `notification_dispatch` row creado | `alert_events` row con tipo=SOBRESTOCK; `notification_dispatch.estado`='PENDIENTE' o 'ENVIADO' |
| AC-001-E1 | Integration | inventory-service | `POST /inventory/movements` con cantidad=0; verificar HTTP 400; `stock_levels.stock_actual` sin cambio; sin row en `inventory_movements` | HTTP 400; `stock_levels.stock_actual` sin modificar |
| AC-001-E2 | Integration | inventory-service | `POST /inventory/movements` con productoId de producto INACTIVO; verificar respuesta de error | HTTP 409; sin row en `inventory_movements` |
| AC-001-E3 | Integration | inventory-service | `POST /inventory/movements` sin `referenciaDocumento`; verificar HTTP 400 | HTTP 400; campo `referenciaDocumento` en errores de validación |
| AC-002-S1 | Integration | inventory-service (R2DBC PostgreSQL) | `POST /inventory/movements` (tipo=SALIDA, cantidad ≤ stock_actual); verificar `stock_levels.stock_actual` = previo - cantidad; KardexRecord creado | HTTP 201; `stock_levels.stock_actual` reducido; `movimientos` en MongoDB actualizado |
| AC-002-S2 | Integration | inventory-service → alert-service (Kafka) | SALIDA que lleva stock ≤ stock_mínimo; verificar `alert_events.tipo_alerta`='BAJO_STOCK' | `alert_events` row BAJO_STOCK; notificación disparada |
| AC-002-E1 | Integration | inventory-service | `POST /inventory/movements` (tipo=SALIDA, cantidad > stock_actual); verificar HTTP 409 con stock disponible en respuesta; sin cambio en stock | HTTP 409; cuerpo de error incluye `stockDisponible`; `stock_levels` sin cambio |
| AC-002-E2 | Integration | inventory-service | SALIDA sobre producto INACTIVO | HTTP 409; sin `inventory_movements` row |
| AC-002-E3 | Integration | inventory-service | SALIDA con cantidad ≤ 0 | HTTP 400 |
| AC-003-S1 | Integration | adjustment-service (R2DBC PostgreSQL) | `POST /adjustments` con motivo no vacío; verificar `adjustment_requests.estado`='PENDIENTE'; `stock_levels` sin cambio; `outbox` row AjusteSolicitado | HTTP 201; `adjustment_requests.estado`=PENDIENTE; stock sin cambio |
| AC-003-S2 | E2E | adjustment-service + inventory-service (Kafka Saga-02) | Aprobar ajuste; verificar `adjustment_requests.estado`='APROBADO'; consumo de `AjusteAprobado` por inventory-service; `stock_levels` actualizado; KardexRecord creado | `adjustment_requests.estado`=APROBADO; `stock_levels.stock_actual` modificado; `inventory_movements` row tipo=AJUSTE |
| AC-003-S3 | Integration | adjustment-service | Rechazar ajuste; verificar `adjustment_requests.estado`='RECHAZADO'; `adjustment_decisions` row con decision='RECHAZADO'; stock sin cambio | HTTP 200; `adjustment_requests.estado`=RECHAZADO; stock sin cambio |
| AC-003-E1 | Integration | adjustment-service | `POST /adjustments` sin motivo o motivo vacío; HTTP 400 | HTTP 400; sin `adjustment_requests` row |
| AC-003-E2 | Integration | adjustment-service (JWT sin rol Supervisor) | `POST /adjustments/{id}/aprobar` con token de Operador; HTTP 403 | HTTP 403; `adjustment_requests.estado` permanece PENDIENTE |
| AC-003-E3 | E2E | integration-service (Saga-02 compensación) | Simular fallo en inventory-service al aplicar stock tras AjusteAprobado; verificar `POST /adjustments/{id}/compensar` ejecutado; `adjustment_requests.estado`='ERROR'; `audit_log` row tipo=COMPENSAR | `adjustment_requests.estado`=ERROR; `inventory_movements` sin row de ajuste aplicado; `audit_log` row de compensación |
| AC-004-S1 | Integration | alert-service (Kafka consumer) + integration-service | Publicar `StockActualizado` con stock ≤ stock_mínimo; verificar `alert_events` creado; REST a integration-service invocado | `alert_events.tipo_alerta`='BAJO_STOCK'; `notification_dispatch` row |
| AC-004-S2 | Integration | alert-service (Kafka consumer) | Publicar `StockActualizado` con stock ≥ stock_máximo | `alert_events.tipo_alerta`='SOBRESTOCK' |
| AC-004-S3 | Integration | alert-service + integration-service (WireMock servicio externo no disponible) | Simular fallo del servicio de notificaciones (WireMock 503); verificar `alert_events` creado y visible; `notification_dispatch.estado`='FALLIDO'; reintento programado | `alert_events` row creado; `notification_dispatch.intentos` > 0; `alert_events.estado`='ACTIVA' |
| AC-004-E1 | Integration | integration-service (Resilience4j reintentos agotados) | Servicio externo retorna error persistente (WireMock 503 × N reintentos); verificar `notification_dispatch.estado`='FALLIDO'; `audit_log` row de fallo | `notification_dispatch.estado`=FALLIDO; `alert_events.estado`='ACTIVA' en dashboard |
| AC-004-E2 | Integration | catalog-service (regla de dominio) | `PUT /catalog/products/{id}` con `stock_maximo` ≤ `stock_minimo`; HTTP 400 | HTTP 400; `productos` row sin cambio en umbrales |
| AC-005-S1 | E2E | Kong (JWT RS256) + Keycloak | Login con credenciales válidas; obtener JWT; llamar `/inventory/stock` con JWT; HTTP 200 | JWT válido con claims de rol; HTTP 200 en endpoint autorizado |
| AC-005-S2 | Integration | Kong (RBAC) | JWT de Operador en `GET /catalog/products`; HTTP 200. JWT de Operador en `GET /reports` (sin permiso); HTTP 403 | HTTP 200 en endpoints permitidos; HTTP 403 en módulo de reportería |
| AC-005-E1 | Integration | Keycloak | Login con contraseña incorrecta; mensaje genérico sin revelar si fallo en usuario o contraseña | HTTP 401; sin JWT; mensaje genérico |
| AC-005-E2 | Integration | Keycloak | Login con usuario INACTIVO | HTTP 401 |
| AC-005-E3 | Integration | Kong | Enviar JWT expirado a endpoint protegido; HTTP 401 | HTTP 401; sin datos internos en respuesta |
| AC-005-E4 | Integration | Kong + microservicio | JWT válido de Operador en `POST /adjustments/{id}/aprobar`; HTTP 403 | HTTP 403; `adjustment_requests.estado` sin cambio |
| AC-006-S1 | E2E | report-service + report-etl-service (Spark) + report-format-consumer (OpenFaaS) | Gerente solicita reporte `stock-actual` con filtro categoría; polling hasta COMPLETADO; descargar XLSX | `report_requests.estado`='COMPLETADO'; `report_files` row con url_minio; XLSX descargable |
| AC-006-S2 | E2E | report-service + format-consumer | Solicitar reporte `stock-actual` con formato XLSX; verificar archivo descargado | Archivo XLSX con datos de stock al momento de la generación; filtros preservados |
| AC-006-S3 | E2E | report-service + ETL (audit JDBC) | Gerente con permiso auditoria genera reporte `auditoria-operaciones`; verificar `audit_log` consultado vía JDBC | `report_requests.estado`='COMPLETADO'; reporte incluye operaciones con usuario, fecha y valores |
| AC-006-E1 | Integration | Kong (RBAC) | Usuario sin permiso de reportería en `POST /reports`; HTTP 403 | HTTP 403; sin `report_requests` row |
| AC-006-E2 | Integration | report-service (Kafka consumer de fallo ETL) | Publicar evento `ReporteETLFallido` (DE-021); verificar `report_requests.estado`='FALLIDO' | `report_requests.estado`=FALLIDO; `audit_log` row de fallo |
| AC-007-S1 | E2E | integration-service (Camel + WireMock proveedor REST) + inventory-service (Saga-01) | Simular proveedor que confirma reposición (WireMock 200); verificar entrada registrada en inventory-service; stock actualizado; `integration_logs` row | `inventory_movements` row tipo=ENTRADA; `stock_levels` incrementado; `integration_logs.estado`='COMPLETADO' |
| AC-007-E1 | E2E | integration-service (Saga-01 compensación, WireMock timeout) | Proveedor no responde (WireMock delay > timeout); verificar `SolicitudReposicionFallida`; si entrada parcial: `EntradaRevertida`; stock consistente | `integration_logs.estado`='FALLIDO'; stock sin cambio; `audit_log` row de compensación |
| AC-007-E2 | Integration | integration-service | Solicitar reposición con proveedor INACTIVO; HTTP 404/409 | HTTP 404/409; sin saga iniciada; sin `integration_logs` row de solicitud |

### Estrategia de Prueba por Capa

| Capa | Herramienta | Alcance |
|---|---|---|
| Unit | JUnit 5 + Mockito | Dominio (aggregates, value objects, reglas de negocio); sin infraestructura |
| Integration | Spring Boot Test + Testcontainers (PostgreSQL, MongoDB, Kafka) | Adaptadores de persistencia (R2DBC); projection consumers Kafka; Outbox relay |
| Contract | Pact (Consumer-Driven Contracts) | Contratos REST entre microservicios internos (alert-service → integration-service) |
| E2E | REST Assured + Testcontainers full-stack | Flujos completos: registro de movimiento → alerta → notificación; Saga-01; Saga-02; generación de reporte |
| E2E Sagas | REST Assured + WireMock (NodePort 9999) + Testcontainers | Flujos de compensación Saga-01 y Saga-02 con inyección de fallos |
| Carga | k6 | 500 usuarios concurrentes; SLA p95 < 2 s consultas, < 3 s escrituras; endpoints `/inventory/stock`, `/inventory/movements`, `/inventory/kardex/{id}` |

### Convención de Nombrado de Tests de Integración

Los tests de integración que validan criterios ATDD deben incluir el ID del criterio en `@DisplayName` o en el nombre del método para trazabilidad directa en el reporte de CI:

```java
@Test
@DisplayName("AC-001-S1: Entrada válida incrementa stock y crea KardexRecord")
void ac001S1_entradaValidaIncrementaStockYCreaKardex() { ... }

@Test
@DisplayName("AC-003-E3: Compensación Saga-02 revierte ajuste aprobado ante fallo en Inventory")
void ac003E3_compensacionSaga02RevierteAjuste() { ... }
```
