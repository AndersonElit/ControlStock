# Strategic Design Document — Dominio y Comportamiento

**Proyecto:** ControlStock | Parte del conjunto SDD — etapa Strategic Design / Pre-Design del SDLC.
Documentos complementarios: `SDD-ControlStock-security.md` · `SDD-ControlStock-architecture.md`

---

## 1. Introducción

### Propósito

Este documento modela el dominio de negocio de ControlStock, establece el lenguaje ubicuo del sistema, define los bounded contexts y sus límites, describe los eventos de dominio y formaliza el comportamiento esperado mediante criterios de aceptación ATDD y escenarios BDD.

### Objetivo de la Etapa

Establecer las bases conceptuales y de dominio que guiarán el diseño técnico: separación clara de responsabilidades entre contextos, contrato de comportamiento verificable y vocabulario común entre negocio, desarrollo y QA.

### Contexto del Sistema

ControlStock es un sistema web centralizado de gestión de inventario para el dominio de Retail / Logística. Reemplaza hojas de cálculo y procesos manuales, proveyendo control de stock en tiempo real, trazabilidad completa de movimientos, automatización de alertas, integración con proveedores externos y reportería ejecutiva exportable.

### Relación con el SDLC

Este documento es salida de la etapa de Strategic Design y entrada requerida para la etapa de Diseño Técnico. Se basa en `SRS-ControlStock v1.0` y `ADC-ControlStock v1.0`.

---

## 2. Visión del Dominio

El dominio central de ControlStock es la **gestión de inventario operativo**. Sus capacidades principales son:

- **Control de existencias en tiempo real:** cada movimiento de mercancía actualiza inmediatamente el stock disponible del producto.
- **Trazabilidad completa de movimientos:** todo cambio de stock queda registrado de forma permanente e inmutable en el Kardex del producto.
- **Automatización de alertas:** el sistema evalúa automáticamente los umbrales de stock tras cada movimiento y notifica a los actores relevantes.
- **Gestión del ciclo de abastecimiento:** integración con proveedores externos para consultar disponibilidad y emitir solicitudes de reposición.
- **Visibilidad ejecutiva:** dashboard de KPIs e informes exportables para la toma de decisiones estratégicas y operativas.
- **Auditoría de operaciones:** registro inmutable de toda operación ejecutada, incluyendo usuario responsable y valores antes/después.

El dominio opera con múltiples roles de usuario (Operador, Supervisor, Administrador, Gerente/Analista) y dependencias externas (proveedores de productos, servicios de notificación, consumidores de la API pública).

---

## 3. Ubiquitous Language

| Término | Definición | Contexto |
|---------|-----------|---------|
| Producto | Artículo catalogado del inventario, identificado por código único, con atributos de stock y umbrales configurables | Catalog, Inventory |
| Categoría | Agrupación funcional de productos; cada producto pertenece a exactamente una categoría | Catalog |
| Stock | Cantidad disponible de un producto en inventario en un momento determinado | Inventory |
| Stock Mínimo | Umbral inferior de stock; al alcanzarlo o caer por debajo, el sistema genera una AlertaBajoStock | Inventory, Alert |
| Stock Máximo | Umbral superior de stock; al superarlo, el sistema genera una AlertaSobrestock | Inventory, Alert |
| Movimiento de Inventario | Operación atómica que modifica el stock de un producto: Entrada, Salida o Ajuste aprobado | Inventory |
| Entrada de Inventario | Movimiento que incrementa el stock (compra, devolución de cliente, ajuste de apertura) | Inventory |
| Salida de Inventario | Movimiento que reduce el stock (venta, consumo interno, merma) | Inventory |
| Ajuste de Inventario | Corrección de discrepancias entre stock físico y registrado; requiere aprobación de Supervisor o Administrador antes de impactar el stock | Adjustment |
| Kardex | Registro histórico cronológico de todos los movimientos de un producto, con saldo acumulado tras cada operación | Inventory |
| Saldo de Kardex | Stock acumulado del producto calculado tras la aplicación de cada movimiento | Inventory |
| Anulación de Movimiento | Operación que cancela un movimiento registrado; el movimiento permanece visible en el Kardex con estado "anulado" | Inventory |
| Alerta de Stock | Notificación generada automáticamente cuando el stock alcanza o supera los umbrales configurados | Alert |
| AlertaBajoStock | Alerta generada cuando `stock_actual ≤ stock_mínimo` | Alert |
| AlertaSobrestock | Alerta generada cuando `stock_actual ≥ stock_máximo` | Alert |
| Proveedor | Entidad que suministra productos al inventario; puede integrarse vía API REST o intercambio de archivos | Supplier |
| Solicitud de Reposición | Pedido emitido al proveedor para reponer el stock de uno o más productos | Integration |
| RBAC | Role-Based Access Control; los permisos se asignan por rol, no directamente por usuario | IAM |
| Rol | Conjunto de permisos que determina qué operaciones puede ejecutar un usuario en cada módulo | IAM |
| Permiso | Autorización granular sobre un módulo y una operación (leer, crear, modificar, ejecutar) | IAM |
| Dashboard | Panel ejecutivo con KPIs de inventario actualizados en tiempo real | Reporting |
| KPI | Key Performance Indicator; indicador clave para monitorear el estado del inventario | Reporting |
| Reporte | Documento parametrizable con datos filtrados del inventario, exportable en PDF/XLSX/CSV | Reporting |
| ReportSchema | Definición estructural de un tipo de reporte: columnas, fuente de datos y formato de salida | Reporting |
| ReportType | Clasificación del reporte: `stock-actual`, `movimientos-periodo`, `kardex-producto`, `stock-bajo-minimo`, `proveedores-actividad`, `auditoria-operaciones` | Reporting |
| ColumnSpec | Especificación de una columna en un ReportSchema: nombre, tipo de dato, fuente y transformación requerida | Reporting |
| Read Model | Proyección desnormalizada en MongoDB del estado del dominio, optimizada para consultas de Kardex, dashboard y reportería | Inventory, Reporting |
| Outbox | Tabla en PostgreSQL que almacena eventos de dominio pendientes de publicación en Kafka (Transactional Outbox pattern) | Inventory, Adjustment |
| Aprobación de Ajuste | Acción del Supervisor o Administrador que autoriza la aplicación de un ajuste al stock | Adjustment |
| Rechazo de Ajuste | Acción del Supervisor o Administrador que deniega un ajuste; el stock no se modifica | Adjustment |
| Auditoría | Registro automático e inmutable de toda operación ejecutada: entidad, usuario, timestamp y valores antes/después | Audit |
| Trazabilidad | Capacidad del sistema de rastrear el origen, historial y estado de cualquier operación o entidad | Audit, Inventory |

---

## 4. Bounded Contexts

### BC-01 — Identity & Access (IAM)

**Propósito:** Gestión centralizada de identidad, autenticación y control de acceso basado en roles.

**Responsabilidades:**
- Autenticar usuarios mediante OIDC/OAuth 2.0 (Keycloak realm `controlstock`).
- Gestionar usuarios, roles y permisos (RBAC granular por módulo y operación).
- Emitir y validar tokens JWT RS256.
- Revocar sesiones activas y soportar recuperación de contraseña.

**Entidades principales:** Usuario, Rol, Permiso, Sesión.

**Límites:** No contiene lógica de negocio de inventario. Es upstream para todos los demás contextos: sus tokens JWT son la fuente de verdad de identidad en cada petición, validada por Kong.

**Datos que posee (Database-per-Service):** `controlstock_iam` (PostgreSQL) — tablas: `usuarios`, `roles`, `permisos`, `asignaciones_rol_usuario`.

---

### BC-02 — Catalog

**Propósito:** Gestión del catálogo maestro de productos y categorías.

**Responsabilidades:**
- Alta, modificación e inactivación de productos y categorías.
- Validación de unicidad de código de producto.
- Garantizar que una categoría con productos activos no se inactive.
- Garantizar invariante de negocio: `stock_mínimo < stock_máximo`.

**Entidades principales:** Producto, Categoría.

**Límites:** No gestiona stock ni movimientos. Los eventos que emite notifican al contexto de Inventory.

**Datos que posee:** `controlstock_catalog` (PostgreSQL) — tablas: `productos`, `categorias`.

---

### BC-03 — Inventory

**Propósito:** Control de stock en tiempo real, registro de movimientos y generación del Kardex.

**Responsabilidades:**
- Mantener el `StockLevel` actualizado por producto.
- Registrar entradas y salidas de inventario.
- Impedir salidas cuando `cantidad_solicitada > stock_disponible`.
- Crear un `KardexRecord` append-only tras cada movimiento.
- Publicar eventos de dominio vía Outbox → Kafka.
- Materializar el read model en MongoDB vía projection consumer.

**Entidades principales:** StockLevel, InventoryMovement, KardexRecord.

**Límites:** No gestiona el flujo de aprobación de ajustes (BC-04). No envía alertas directamente (BC-05). Solo aplica el impacto en stock de un ajuste ya aprobado.

**Datos que posee:**
- `controlstock_inventory` (PostgreSQL) — tablas: `stock_levels`, `inventory_movements`, `outbox`.
- `controlstock_readmodel` (MongoDB) — colecciones: `kardex`, `movimientos`, `stock` (read model CQRS; también usado por Reporting).

---

### BC-04 — Adjustment

**Propósito:** Gestión del flujo de ajustes de inventario con aprobación obligatoria.

**Responsabilidades:**
- Crear `AdjustmentRequest` en estado Pendiente con motivo obligatorio.
- Notificar al Supervisor sobre ajustes pendientes.
- Registrar la decisión de aprobación o rechazo.
- Publicar `AjusteAprobado` o `AjusteRechazado` como eventos de dominio.

**Entidades principales:** AdjustmentRequest, AdjustmentDecision.

**Límites:** No modifica directamente el stock. La modificación ocurre en BC-03 como respuesta al evento `AjusteAprobado`.

**Datos que posee:** `controlstock_adjustment` (PostgreSQL) — tablas: `adjustment_requests`, `adjustment_decisions`, `outbox`.

---

### BC-05 — Alert

**Propósito:** Motor de alertas automáticas de inventario.

**Responsabilidades:**
- Evaluar los umbrales de stock configurados por producto tras cada evento `StockActualizado`.
- Generar `AlertaBajoStock` y `AlertaSobrestock` cuando se cumplen las condiciones.
- Registrar las alertas generadas.
- Solicitar el envío de notificaciones al contexto de Integration vía REST interno.

**Entidades principales:** AlertRule, AlertEvent.

**Límites:** No envía notificaciones directamente. No gestiona la configuración de umbrales (responsabilidad de BC-02/BC-03).

**Datos que posee:** `controlstock_alert` (PostgreSQL) — tablas: `alert_rules`, `alert_events`.

---

### BC-06 — Supplier

**Propósito:** Gestión del catálogo de proveedores y su configuración de integración.

**Responsabilidades:**
- Registrar, modificar e inactivar proveedores.
- Almacenar la configuración de integración por proveedor (protocolo, referencias a secretos en Vault).
- Impedir la eliminación de proveedores con movimientos de inventario asociados.

**Entidades principales:** Supplier, IntegrationConfig.

**Límites:** No ejecuta integraciones directamente. La configuración almacenada aquí es consumida por BC-09 para establecer la conectividad con cada proveedor.

**Datos que posee:** `controlstock_supplier` (PostgreSQL) — tablas: `suppliers`, `integration_configs`.

---

### BC-07 — Reporting

**Propósito:** Orquestación de la generación de reportes, gestión del catálogo de esquemas y producción de archivos exportables.

**Responsabilidades:**
- Gestionar el catálogo de esquemas de reporte (`ReportSchema` por `ReportType`).
- Recibir y gestionar el ciclo de vida de solicitudes de reporte (`ReportRequest`).
- Disparar el ETL (`report-etl-service`) vía evento Kafka.
- Coordinar la generación del archivo final mediante OpenFaaS `report-format-consumer`.
- Proveer acceso a los archivos generados en MinIO a usuarios autorizados.

**Entidades principales:** ReportRequest, ReportSchema, ReportFile.

**Límites:** Lee del read model MongoDB (`controlstock_readmodel`) a través del ETL y de `controlstock_audit` vía JDBC para datos de auditoría. No accede a las BDs operacionales de otros contextos.

**Datos que posee:**
- `controlstock_reporting` (PostgreSQL) — tablas: `report_schema_catalog`, `report_requests`, `report_files`.
- MinIO bucket `controlstock-reports` — archivos Parquet, XLSX, CSV y PDF generados.

---

### BC-08 — Audit

**Propósito:** Registro inmutable y centralizado de todas las operaciones del sistema.

**Responsabilidades:**
- Consumir eventos de dominio de todos los contextos desde Kafka.
- Persistir cada operación como `AuditRecord` append-only con usuario, timestamp, entidad, operación y valores antes/después.
- Proveer consulta de la bitácora a usuarios autorizados.

**Entidades principales:** AuditRecord.

**Límites:** Solo escribe (append). Ningún proceso del sistema puede modificar ni eliminar un `AuditRecord`.

**Datos que posee:** `controlstock_audit` (PostgreSQL) — tabla: `audit_log` (append-only; sin operaciones DELETE/UPDATE sobre registros existentes).

---

### BC-09 — Integration

**Propósito:** Anti-Corruption Layer (ACL) centralizado entre ControlStock y todos los sistemas externos; orquestador de sagas distribuidas.

**Responsabilidades:**
- Gestionar la conectividad con el servicio de notificaciones externo (email/mensajería) vía Apache Camel.
- Gestionar la integración con proveedores externos (REST y archivo FTP/SFTP) vía Camel EIP.
- Exponer la API pública de ControlStock a sistemas externos consumidores (RF-020), coordinada con Kong.
- Orquestar las sagas distribuidas que cruzan múltiples contextos (Camel Saga EIP + Narayana LRA).
- Registrar el resultado de cada integración para trazabilidad.
- Gestionar reintentos de notificaciones fallidas con backoff exponencial.

**Entidades principales:** IntegrationRequest, SagaInstance, NotificationDispatch, SupplierResponse.

**Límites:** Actúa como mediador; nunca accede directamente a las bases de datos de otros bounded contexts. Se comunica vía Kafka (eventos) o REST interno K3s.

**Datos que posee:** `controlstock_integration` (PostgreSQL) — tablas: `integration_logs`, `saga_state`, `notification_dispatch`, `outbox`.

---

## 5. Context Map

### Relaciones entre Bounded Contexts Internos

| Upstream | Downstream | Patrón | Canal | Descripción |
|----------|-----------|--------|-------|-------------|
| IAM (BC-01) | Todos los BC | Shared Kernel (JWT claims) | Kong JWT Plugin RS256 | Todos los contextos validan identidad y roles a través del JWT emitido por Keycloak; Kong intercepta y valida antes de enrutar |
| Catalog (BC-02) | Inventory (BC-03) | Customer / Supplier | Kafka: `ProductoInactivado`, `ProductoActualizado` | Inventory sincroniza referencias locales; bloquea movimientos sobre productos inactivados |
| Inventory (BC-03) | Alert (BC-05) | Customer / Supplier | Kafka: `StockActualizado` | Alert consume eventos de stock para evaluar umbrales y generar alertas |
| Inventory (BC-03) | Audit (BC-08) | Customer / Supplier | Kafka: `EntradaRegistrada`, `SalidaRegistrada` | Audit persiste cada movimiento como registro inmutable |
| Inventory (BC-03) | Reporting (BC-07) | Conformist | MongoDB read model `controlstock_readmodel` | El ETL de Reporting lee exclusivamente del read model materializado por Inventory |
| Adjustment (BC-04) | Inventory (BC-03) | Saga (Customer / Supplier) | Kafka (saga): `AjusteAprobado` | Inventory aplica el impacto en stock solo tras recibir `AjusteAprobado`; flujo coordinado por Saga-02 |
| Adjustment (BC-04) | Audit (BC-08) | Customer / Supplier | Kafka: `AjusteSolicitado`, `AjusteAprobado`, `AjusteRechazado` | Audit persiste el ciclo completo del ajuste |
| Alert (BC-05) | Integration (BC-09) | Customer / Supplier | REST interno K3s | Alert solicita el envío de notificaciones al `integration-service` |
| Supplier (BC-06) | Integration (BC-09) | Customer / Supplier | Kafka: `ProveedorActualizado` + REST | Integration consume la configuración de proveedor para establecer conectividad |
| Integration (BC-09) | Inventory (BC-03) | Saga Coordinator | Kafka (saga): resultado de reposición | Integration ordena a Inventory crear la entrada confirmada por el proveedor (Saga-01) |
| Reporting (BC-07) | Audit (BC-08) | Customer / Supplier (solo lectura) | JDBC (PostgreSQL `controlstock_audit`) | El ETL accede a `audit_log` para el reporte de auditoría de operaciones |

### Sistemas Externos — Anti-Corruption Layer (ACL)

Todo sistema externo se modela como contexto upstream. BC-09 (`integration-service`) actúa como ACL, traduciendo modelos externos al lenguaje ubicuo de ControlStock.

| Sistema Externo (Upstream) | Dirección | Criticidad | ACL / Mediador |
|---------------------------|----------|------------|---------------|
| Servicio de Notificaciones (email / SMTP relay / SendGrid) | Saliente (consumo) | Alta | `integration-service` — traduce `AlertaGenerada` → llamada REST/SMTP al proveedor; gestiona reintentos |
| APIs REST de Proveedores Externos | Saliente (consumo) | Media | `integration-service` — Camel `http` component; traduce `SolicitudReposicion` al formato de cada proveedor |
| Archivos FTP/SFTP de Proveedores sin API | Bidireccional | Media | `integration-service` — Camel `file` component; adapta el modelo de archivo al lenguaje ubicuo |
| Sistemas Externos Consumidores de la API Pública (RF-020) | Entrante | Alta | Kong API Gateway — valida tokens de API independientes; `integration-service` media el contrato público REST |

### Flujos de Saga (Transacciones Distribuidas)

#### Saga-01 — Reposición de Inventario vía Proveedor Externo

**Coordinador:** Integration (BC-09) — Apache Camel Saga EIP + Narayana LRA

| Paso | Contexto | Acción | Evento de Compensación |
|------|---------|--------|----------------------|
| 1 | Integration (BC-09) | Enviar `SolicitudReposicion` al proveedor externo | `SolicitudReposicionCancelada` |
| 2 | Inventory (BC-03) | Registrar `EntradaRegistrada` por cantidad confirmada por proveedor | `EntradaRevertida` (DE-019) |
| 3 | Alert (BC-05) | Evaluar umbrales y generar alerta si corresponde | (informativo; sin compensación) |

**Condición de compensación:** Si la confirmación del proveedor falla o el paso de entrada en Inventory falla, el coordinador emite `EntradaRevertida` (DE-019) para revertir cualquier cambio de stock aplicado.

---

#### Saga-02 — Ajuste de Inventario con Aprobación

**Coordinador:** Adjustment (BC-04) coordina la decisión; Narayana LRA garantiza el cruce con Inventory.

| Paso | Contexto | Acción | Evento de Compensación |
|------|---------|--------|----------------------|
| 1 | Adjustment (BC-04) | Crear `AdjustmentRequest` en estado Pendiente | — |
| 2 | Adjustment (BC-04) | Supervisor aprueba → emite `AjusteAprobado` | `AjusteRevertido` (DE-010) |
| 3 | Inventory (BC-03) | Aplicar impacto en stock y crear `KardexRecord` | `AjusteRevertido` (DE-010) |

**Condición de compensación:** Si la actualización del stock en Inventory falla tras `AjusteAprobado`, se emite `AjusteRevertido` (DE-010) y el `AdjustmentRequest` transiciona a estado Error.

---

## 6. Modelos de Dominio

## Aggregate: Producto (Catalog BC)

### Responsabilidad
Fuente de verdad del catálogo maestro de artículos de inventario.

### Entidades
- Producto (aggregate root)
- Categoría (referenciada por ID)

### Value Objects
- CodigoProducto (código único, inmutable tras creación)
- NombreProducto
- UmbralStock (mínimo y máximo; invariante: mínimo < máximo)
- EstadoProducto (Activo / Inactivo)

### Reglas importantes
- El código de producto es único en todo el catálogo.
- Un producto inactivo no puede recibir nuevos movimientos de inventario.
- El sistema impide guardar una configuración donde `stock_máximo ≤ stock_mínimo`.

---

## Aggregate: StockLevel (Inventory BC)

### Responsabilidad
Representa el estado actual del stock de un producto. Garantiza la integridad del stock en tiempo real.

### Entidades
- StockLevel (aggregate root, uno por producto)

### Value Objects
- CantidadStock (siempre ≥ 0)
- ProductoRef (referencia al producto propietario en Catalog)

### Reglas importantes
- El stock nunca puede ser negativo.
- Una salida solo se permite si `cantidad_salida ≤ stock_disponible`.
- El stock se actualiza de forma atómica con el registro del movimiento.

---

## Aggregate: InventoryMovement (Inventory BC)

### Responsabilidad
Representa un movimiento de inventario registrado de forma inmutable. Cada instancia es un hecho consumado del dominio.

### Entidades
- InventoryMovement (aggregate root)

### Value Objects
- TipoMovimiento (Entrada / Salida / Ajuste)
- CantidadMovimiento (positiva para entradas; negativa para salidas y ajustes negativos)
- ReferenciaDocumento
- SaldoResultante (stock del Kardex tras el movimiento)
- EstadoMovimiento (Activo / Anulado)

### Reglas importantes
- Un movimiento registrado no puede eliminarse; solo anularse con estado visible en el Kardex.
- El saldo resultante es el stock previo ± cantidad del movimiento.

---

## Aggregate: AdjustmentRequest (Adjustment BC)

### Responsabilidad
Gestiona el ciclo de vida de una solicitud de ajuste, desde la creación hasta la decisión de aprobación o rechazo.

### Entidades
- AdjustmentRequest (aggregate root)
- AdjustmentDecision

### Value Objects
- EstadoAjuste (Pendiente / Aprobado / Rechazado / Error)
- MotivoAjuste (obligatorio; no puede ser vacío)
- CantidadAjuste (positiva o negativa)

### Reglas importantes
- El motivo del ajuste es obligatorio; un ajuste sin motivo no puede crearse.
- El stock solo cambia cuando el estado transiciona a Aprobado.
- Solo usuarios con rol Supervisor o Administrador pueden aprobar o rechazar ajustes.

---

## Aggregate: AlertRule (Alert BC)

### Responsabilidad
Define las condiciones de disparo de alertas y registra los eventos de alerta generados para un producto.

### Entidades
- AlertRule (aggregate root, uno por producto)
- AlertEvent

### Value Objects
- TipoAlerta (BajoStock / Sobrestock)
- EstadoAlerta (Activa / Reconocida / Resuelta)

### Reglas importantes
- `AlertaBajoStock` se genera cuando `stock_actual ≤ stock_mínimo`.
- `AlertaSobrestock` se genera cuando `stock_actual ≥ stock_máximo`.
- Las alertas quedan registradas incluso si el envío de notificación externa falla.

---

## Aggregate: Supplier (Supplier BC)

### Responsabilidad
Representa un proveedor de inventario con su configuración de integración.

### Entidades
- Supplier (aggregate root)
- IntegrationConfig

### Value Objects
- IdentificacionFiscal
- MetodoIntegracion (REST / Archivo)
- EstadoProveedor (Activo / Inactivo)

### Reglas importantes
- Un proveedor con movimientos de inventario asociados no puede eliminarse; solo inactivarse.
- Las credenciales de integración se referencian en Vault; nunca se almacenan en texto plano en la BD.

---

## Aggregate: AuditRecord (Audit BC)

### Responsabilidad
Registro inmutable de una operación ejecutada en el sistema.

### Entidades
- AuditRecord (aggregate root)

### Value Objects
- TimestampOperacion (UTC, inmutable)
- UsuarioRef
- EntidadAfectada
- OperacionEjecutada (Crear / Modificar / Inactivar / Mover / Anular)
- ValorAnterior / ValorPosterior (JSON)

### Reglas importantes
- Un `AuditRecord` nunca puede ser modificado ni eliminado por ningún usuario ni proceso.
- Toda operación que modifique datos genera automáticamente un `AuditRecord`.

---

## Aggregate: ReportRequest (Reporting BC)

### Responsabilidad
Representa una solicitud de generación de reporte y su ciclo de vida desde la solicitud hasta el archivo disponible.

### Entidades
- ReportRequest (aggregate root)
- ReportSchema
- ReportFile

### Value Objects
- ReportType (`stock-actual` / `movimientos-periodo` / `kardex-producto` / `stock-bajo-minimo` / `proveedores-actividad` / `auditoria-operaciones`)
- ParametrosReporte (filtros: rango de fechas, categoría, producto)
- EstadoReporte (Solicitado / Procesando / Completado / Fallido)
- FormatoSalida (PDF / XLS / CSV)

### Reglas importantes
- Un reporte solo puede descargarse por usuarios con permiso explícito sobre el módulo de reportería.
- Los reportes exportados preservan los filtros aplicados y los datos completos al momento de la generación.

---

## 7. Eventos de Dominio

## DE-001 — ProductoCreado

Descripción:
Un nuevo producto fue registrado en el catálogo con todos sus atributos obligatorios.

Disparadores:
- Un Administrador o Supervisor completa exitosamente el alta de un nuevo producto.

Consecuencias:
- El producto queda disponible para recibir movimientos de inventario.
- Audit registra la creación.

---

## DE-002 — ProductoActualizado

Descripción:
Los atributos de un producto existente fueron modificados (nombre, umbrales, categoría u otros).

Disparadores:
- Un Administrador o Supervisor modifica el producto y guarda los cambios.

Consecuencias:
- Inventory consume el evento para sincronizar referencias locales, especialmente cambios de umbrales de stock.
- Audit registra la modificación.

---

## DE-003 — ProductoInactivado

Descripción:
Un producto fue marcado como inactivo en el catálogo.

Disparadores:
- Un Administrador inactiva el producto.

Consecuencias:
- Inventory bloquea cualquier nuevo movimiento sobre el producto inactivado.
- Audit registra la operación.

---

## DE-004 — EntradaRegistrada

Descripción:
Se registró una entrada de inventario que incrementa el stock de un producto.

Disparadores:
- Un Operador completa el registro de entrada.
- El sistema registra automáticamente una entrada como resultado de una confirmación de proveedor (Saga-01).

Consecuencias:
- `StockLevel` del producto se incrementa.
- `KardexRecord` creado (append) con saldo resultante.
- `StockActualizado` (DE-006) emitido.
- Audit registra la operación.

**Evento de compensación:** DE-019 — EntradaRevertida (aplica en Saga-01).

---

## DE-005 — SalidaRegistrada

Descripción:
Se registró una salida de inventario que reduce el stock de un producto.

Disparadores:
- Un Operador completa el registro de salida con stock disponible suficiente.

Consecuencias:
- `StockLevel` del producto se reduce.
- `KardexRecord` creado (append).
- `StockActualizado` (DE-006) emitido.
- Audit registra la operación.

---

## DE-006 — StockActualizado

Descripción:
El stock disponible de un producto cambió como resultado de una entrada, salida o ajuste aprobado.

Disparadores:
- Publicado por Inventory tras cualquier modificación exitosa del stock.

Consecuencias:
- Alert evalúa los umbrales del producto y genera alertas si corresponde.
- El read model en MongoDB es actualizado vía Outbox → Kafka → projection consumer.

---

## DE-007 — AjusteSolicitado

Descripción:
Un Operador creó una solicitud de ajuste de inventario. El ajuste queda en estado Pendiente, sin impactar el stock.

Disparadores:
- Un Operador completa el formulario de ajuste con motivo obligatorio.

Consecuencias:
- `AdjustmentRequest` creado en estado Pendiente.
- El Supervisor recibe notificación de ajuste pendiente.
- Audit registra la creación del ajuste.

---

## DE-008 — AjusteAprobado

Descripción:
Un Supervisor o Administrador aprobó un ajuste pendiente. El ajuste puede ahora impactar el stock.

Disparadores:
- Un Supervisor o Administrador aprueba el `AdjustmentRequest` en estado Pendiente.

Consecuencias:
- Inventory aplica el cambio de stock (inicia paso 3 de Saga-02).
- `KardexRecord` creado con el movimiento de ajuste.
- Audit registra la aprobación.

**Evento de compensación:** DE-010 — AjusteRevertido.

---

## DE-009 — AjusteRechazado

Descripción:
Un Supervisor o Administrador rechazó un ajuste pendiente. El stock no es modificado.

Disparadores:
- Un Supervisor o Administrador ejecuta el rechazo del `AdjustmentRequest`.

Consecuencias:
- `AdjustmentRequest` queda en estado Rechazado.
- El stock no cambia.
- Audit registra el rechazo con el motivo del mismo.

---

## DE-010 — AjusteRevertido

Descripción:
Un ajuste previamente aprobado fue revertido como compensación en Saga-02 por fallo en la actualización del stock.

Disparadores:
- El coordinador de Saga-02 detecta un fallo en Inventory al aplicar el impacto del ajuste tras `AjusteAprobado`.

Consecuencias:
- `AdjustmentRequest` transiciona a estado Error.
- El stock no refleja el ajuste fallido.
- Audit registra el evento de compensación.

---

## DE-011 — AlertaGenerada

Descripción:
El motor de alertas generó una alerta de stock para un producto.

Disparadores:
- `StockActualizado` recibido con valor que cumple condición de bajo stock o sobrestock.

Consecuencias:
- `AlertEvent` registrado en la BD.
- Se solicita envío de notificación al `integration-service`.
- La alerta queda visible en el dashboard con fecha, producto y tipo.

---

## DE-012 — AlertaBajoStock

Descripción:
Stock disponible de un producto alcanzó o cayó por debajo del umbral mínimo.

Disparadores:
- `StockLevel` actualizado con `stock_actual ≤ stock_mínimo`.

Consecuencias:
- Subtipo de `AlertaGenerada` (DE-011) con tipo BajoStock.

---

## DE-013 — AlertaSobrestock

Descripción:
Stock disponible de un producto superó el umbral máximo configurado.

Disparadores:
- `StockLevel` actualizado con `stock_actual ≥ stock_máximo`.

Consecuencias:
- Subtipo de `AlertaGenerada` (DE-011) con tipo Sobrestock.

---

## DE-014 — NotificacionEnviada

Descripción:
El `integration-service` confirmó el envío exitoso de una notificación al servicio externo.

Disparadores:
- El servicio de notificaciones externo retorna respuesta de éxito.

Consecuencias:
- `NotificationDispatch` queda en estado Enviado.
- `IntegrationRequest` registra el resultado.

---

## DE-015 — NotificacionFallida

Descripción:
El envío de una notificación al servicio externo falló (timeout, error del proveedor o servicio no disponible).

Disparadores:
- El servicio de notificaciones retorna error o no responde dentro del timeout.

Consecuencias:
- `NotificationDispatch` registra el intento fallido.
- El sistema reintenta con backoff exponencial según política configurada.
- Audit registra el fallo.

---

## DE-016 — SolicitudReposicionEnviada

Descripción:
Una solicitud de reposición fue enviada al proveedor externo (paso 1 de Saga-01).

Disparadores:
- `integration-service` envía la solicitud al proveedor vía REST o archivo.

Consecuencias:
- `IntegrationRequest` registrado. Sistema espera confirmación del proveedor.

---

## DE-017 — SolicitudReposicionConfirmada

Descripción:
El proveedor externo confirmó la solicitud de reposición.

Disparadores:
- Respuesta exitosa del proveedor recibida por `integration-service`.

Consecuencias:
- Saga-01 avanza al paso 2: registro de entrada en Inventory.

---

## DE-018 — SolicitudReposicionFallida

Descripción:
La solicitud de reposición no pudo completarse (error del proveedor, timeout o fallo de archivo).

Disparadores:
- El proveedor retorna error o el timeout de la integración expira.

Consecuencias:
- Saga-01 ejecuta compensación. Si ya se registró una entrada, se emite `EntradaRevertida` (DE-019).

---

## DE-019 — EntradaRevertida

Descripción:
Una entrada de inventario fue revertida como compensación en Saga-01.

Disparadores:
- El coordinador de Saga-01 detecta `SolicitudReposicionFallida` o fallo en el proceso de alertas.

Consecuencias:
- `StockLevel` reducido por la cantidad de la entrada revertida.
- `KardexRecord` de reversión creado (append, tipo Anulación).
- Audit registra el evento de compensación.

---

## DE-020 — ReporteParquetGenerado

Descripción:
El ETL (`report-etl-service`, Spark) completó la transformación de datos y generó un archivo `.parquet` en MinIO.

Disparadores:
- Job Spark completa la extracción desde el read model MongoDB (y `controlstock_audit` vía JDBC si aplica).

Consecuencias:
- Evento publicado en Kafka con URL del `.parquet` y formato destino (XLS/CSV).
- OpenFaaS `report-format-consumer` consume el evento y genera el archivo final en MinIO.

---

## DE-021 — ReporteETLFallido

Descripción:
El job ETL falló durante la extracción o transformación de datos.

Disparadores:
- Excepción durante el job Spark (lectura del read model, transformación, escritura en MinIO).

Consecuencias:
- `ReportRequest` transiciona a estado Fallido.
- Audit registra el fallo.
- Usuario puede reintentar la generación del reporte.

---

## DE-022 — OperacionAuditada

Descripción:
Una operación del sistema fue registrada en el log de auditoría.

Disparadores:
- Cualquier evento de dominio de creación, modificación, inactivación o movimiento de inventario.

Consecuencias:
- `AuditRecord` creado de forma inmutable e irrevocable en `controlstock_audit`.

---

## 8. Workflows de Negocio

## Workflow: Registro de Entrada de Inventario

1. El Operador selecciona "Registrar entrada" en el módulo de inventario.
2. El Operador busca y selecciona el producto (solo productos activos disponibles).
3. El Operador ingresa: cantidad (> 0), tipo de entrada, referencia del documento origen y fecha.
4. El sistema valida que el producto esté activo y que la cantidad sea mayor a cero.
5. El sistema actualiza el `StockLevel` del producto.
6. El sistema crea un `KardexRecord` append-only con el saldo resultante.
7. El sistema publica `EntradaRegistrada` y `StockActualizado` vía Outbox → Kafka.
8. Alert evalúa si el nuevo stock supera el máximo y genera `AlertaSobrestock` si corresponde.
9. Audit registra la operación de forma inmutable.

---

## Workflow: Registro de Salida de Inventario

1. El Operador selecciona "Registrar salida" en el módulo de inventario.
2. El Operador busca y selecciona el producto activo.
3. El Operador ingresa: cantidad (> 0), tipo de salida, referencia del documento origen y fecha.
4. El sistema verifica que `cantidad_solicitada ≤ stock_disponible`. Si no, rechaza la operación con el stock actual visible.
5. El sistema actualiza el `StockLevel`.
6. El sistema crea un `KardexRecord` append-only.
7. El sistema publica `SalidaRegistrada` y `StockActualizado` vía Outbox → Kafka.
8. Alert evalúa si el nuevo stock cae al nivel mínimo o por debajo; genera `AlertaBajoStock` si corresponde.
9. Audit registra la operación de forma inmutable.

---

## Workflow: Registro y Aprobación de Ajuste (Saga-02)

1. El Operador selecciona "Registrar ajuste"; ingresa producto, cantidad (± ) y motivo obligatorio.
2. El sistema crea `AdjustmentRequest` en estado Pendiente. El stock no cambia.
3. El Supervisor recibe notificación de ajuste pendiente.
4. El Supervisor revisa el ajuste y ejecuta Aprobar o Rechazar con comentario.
5. Si Aprobado: Adjustment publica `AjusteAprobado` → Inventory aplica el cambio de stock → `KardexRecord` creado.
6. Si la actualización del stock falla: Saga-02 emite `AjusteRevertido` (DE-010); el ajuste queda en estado Error.
7. Si Rechazado: `AdjustmentRequest` queda en estado Rechazado; el stock no cambia.
8. Audit registra la decisión y el resultado final.

---

## Workflow: Generación de Alerta de Stock

1. Inventory publica `StockActualizado` tras una entrada, salida o ajuste aprobado.
2. Alert consume el evento y compara `stock_actual` contra los umbrales configurados para el producto.
3. Si `stock_actual ≤ stock_mínimo`: Alert genera `AlertaBajoStock`.
4. Si `stock_actual ≥ stock_máximo`: Alert genera `AlertaSobrestock`.
5. Alert solicita el envío de notificación al `integration-service` vía REST interno.
6. `integration-service` envía la notificación al servicio externo (email/mensajería).
7. `integration-service` registra el estado de entrega (`NotificacionEnviada` o `NotificacionFallida`).
8. La alerta queda visible en el dashboard con fecha, producto y tipo de alerta.

---

## Workflow: Reposición de Inventario vía Proveedor (Saga-01)

1. El sistema (o el Administrador) inicia el proceso de reposición para un producto.
2. `integration-service` recupera la configuración del proveedor desde Supplier (credenciales desde Vault).
3. `integration-service` envía la solicitud de reposición al proveedor (REST o archivo) → `SolicitudReposicionEnviada` (DE-016).
4. Si el proveedor confirma → `SolicitudReposicionConfirmada` (DE-017): `integration-service` ordena a Inventory crear la entrada.
5. Inventory registra la entrada y actualiza el stock → `EntradaRegistrada` (DE-004).
6. Alert evalúa el stock resultante.
7. Si el proveedor falla o el proceso de entrada falla → Saga-01 compensa → `EntradaRevertida` (DE-019) si ya se había registrado una entrada.
8. `integration-service` registra el resultado de la integración en `integration_logs`.

---

## Workflow: Generación de Reporte

1. El Gerente/Analista accede al módulo de reportes, selecciona tipo y parámetros.
2. `report-service` crea un `ReportRequest` y publica el evento de solicitud en Kafka.
3. `report-etl-service` (Spark batch) consume el evento, lee del read model MongoDB (y de `controlstock_audit` para reportes de auditoría).
4. El ETL transforma los datos, genera el archivo `.parquet` en MinIO y publica `ReporteParquetGenerado` (DE-020).
5. La función OpenFaaS `report-format-consumer` consume el evento y genera el archivo en el formato solicitado (XLS/CSV/PDF).
6. `report-service` actualiza el `ReportRequest` a estado Completado con la URL del archivo en MinIO.
7. El usuario descarga el archivo desde el módulo de reportes.

---

## 9. Criterios de Aceptación (ATDD)

## AC-001 — Registro de Entrada de Inventario

**Caso de uso / Capacidad:** CU-001 — Registrar Entrada de Inventario (RF-007)

**Bounded Context:** Inventory (BC-03)

**Regla de negocio asociada:** RN-006 (producto activo), RN-010 (Kardex inmutable)

### Criterios de aceptación — Éxito

| ID | Criterio | Resultado esperado |
|----|----------|--------------------|
| AC-001-S1 | El Operador registra una entrada con producto activo, cantidad > 0, tipo y referencia válidos | El stock del producto se incrementa en la cantidad indicada de forma inmediata; se crea un KardexRecord con saldo resultante; el movimiento es visible en el Kardex |
| AC-001-S2 | Tras la entrada, el nuevo stock supera el umbral máximo configurado del producto | Se genera automáticamente una AlertaSobrestock visible en el dashboard; se envía notificación al canal configurado |

### Criterios de aceptación — Error

| ID | Criterio | Resultado esperado |
|----|----------|--------------------|
| AC-001-E1 | El Operador intenta registrar una entrada con cantidad ≤ 0 | El sistema rechaza la operación con mensaje de validación; el stock no cambia; no se crea ningún KardexRecord |
| AC-001-E2 | El Operador intenta registrar una entrada sobre un producto inactivo | El producto inactivo no aparece en la lista de selección; la operación no puede iniciarse |
| AC-001-E3 | El Operador envía el formulario sin referencia de documento origen | El sistema valida el campo obligatorio; la entrada no se registra hasta completar el campo |

---

## AC-002 — Registro de Salida de Inventario

**Caso de uso / Capacidad:** CU-002 — Registrar Salida de Inventario (RF-008)

**Bounded Context:** Inventory (BC-03)

**Regla de negocio asociada:** RN-003 (no salida sin stock suficiente), RN-006 (producto activo)

### Criterios de aceptación — Éxito

| ID | Criterio | Resultado esperado |
|----|----------|--------------------|
| AC-002-S1 | El Operador registra una salida con stock disponible suficiente y datos completos | El stock se reduce en la cantidad indicada de forma inmediata; KardexRecord creado con saldo actualizado; movimiento visible en el Kardex |
| AC-002-S2 | Tras la salida, el stock cae al nivel mínimo o por debajo | Se genera AlertaBajoStock visible en el dashboard; notificación enviada al canal de alertas configurado |

### Criterios de aceptación — Error

| ID | Criterio | Resultado esperado |
|----|----------|--------------------|
| AC-002-E1 | El Operador intenta registrar una salida con cantidad mayor al stock disponible | El sistema rechaza la operación; muestra el stock disponible actual al usuario; el stock no cambia; no se crea ningún KardexRecord |
| AC-002-E2 | El Operador intenta registrar una salida sobre un producto inactivo | El producto inactivo no está disponible para selección; la operación no puede iniciarse |
| AC-002-E3 | El Operador intenta registrar una salida con cantidad ≤ 0 | El sistema rechaza con mensaje de validación; sin impacto en stock |

---

## AC-003 — Registro y Aprobación de Ajuste de Inventario

**Caso de uso / Capacidad:** CU-003 — Registrar Ajuste de Inventario (RF-009)

**Bounded Context:** Adjustment (BC-04), Inventory (BC-03)

**Regla de negocio asociada:** RN-005 (motivo obligatorio; aprobación requerida)

### Criterios de aceptación — Éxito

| ID | Criterio | Resultado esperado |
|----|----------|--------------------|
| AC-003-S1 | El Operador crea un ajuste con producto activo, cantidad y motivo válidos | AdjustmentRequest en estado Pendiente; el stock no cambia; el Supervisor recibe notificación |
| AC-003-S2 | El Supervisor aprueba el ajuste pendiente | El stock se actualiza según la cantidad del ajuste; KardexRecord creado; AdjustmentRequest en estado Aprobado |
| AC-003-S3 | El Supervisor rechaza el ajuste con comentario de motivo | AdjustmentRequest en estado Rechazado; el stock no cambia; el motivo de rechazo queda en auditoría |

### Criterios de aceptación — Error

| ID | Criterio | Resultado esperado |
|----|----------|--------------------|
| AC-003-E1 | El Operador intenta crear un ajuste sin motivo | El sistema rechaza; campo motivo marcado como obligatorio; la solicitud no se registra |
| AC-003-E2 | Un usuario con rol Operador intenta aprobar un ajuste | El sistema rechaza la operación con HTTP 403; el ajuste permanece en estado Pendiente |
| AC-003-E3 | La actualización de stock en Inventory falla tras AjusteAprobado (compensación Saga-02) | Se emite AjusteRevertido (DE-010); AdjustmentRequest en estado Error; stock no modificado; auditoría registra la compensación |

---

## AC-004 — Alertas Automáticas de Stock

**Caso de uso / Capacidad:** RF-012 — Alertas Automáticas de Inventario

**Bounded Context:** Alert (BC-05), Integration (BC-09)

**Regla de negocio asociada:** RN-004 (alerta automática en umbral mínimo)

### Criterios de aceptación — Éxito

| ID | Criterio | Resultado esperado |
|----|----------|--------------------|
| AC-004-S1 | El stock de un producto cae al umbral mínimo o por debajo tras una salida | AlertaBajoStock generada; visible en el dashboard; notificación enviada al canal configurado |
| AC-004-S2 | El stock de un producto supera el umbral máximo tras una entrada | AlertaSobrestock generada; visible en el dashboard; notificación enviada |
| AC-004-S3 | El servicio externo de notificaciones no está disponible cuando se genera la alerta | La alerta queda registrada en el sistema y visible en el dashboard; el intento fallido queda en notification_dispatch; el sistema reintenta según política |

### Criterios de aceptación — Error

| ID | Criterio | Resultado esperado |
|----|----------|--------------------|
| AC-004-E1 | El servicio externo de notificaciones retorna error persistente (superados reintentos) | NotificacionFallida (DE-015) registrado; la alerta permanece activa en el dashboard; Audit registra los intentos fallidos |
| AC-004-E2 | Un Supervisor intenta configurar stock_máximo ≤ stock_mínimo | El sistema rechaza la configuración con mensaje de error; los umbrales no se actualizan |

---

## AC-005 — Autenticación y Autorización (RBAC)

**Caso de uso / Capacidad:** RF-001 — Autenticación; RF-003 — RBAC

**Bounded Context:** IAM (BC-01)

**Regla de negocio asociada:** RN-001 (solo usuarios autenticados y con rol correspondiente)

### Criterios de aceptación — Éxito

| ID | Criterio | Resultado esperado |
|----|----------|--------------------|
| AC-005-S1 | Un usuario registrado y activo se autentica con credenciales válidas | El sistema emite un token JWT válido; el usuario accede al sistema con los módulos permitidos por su rol |
| AC-005-S2 | Un usuario con rol Operador accede al módulo de registro de movimientos | Acceso concedido; los módulos de administración y reportería gerencial no son accesibles para este rol |

### Criterios de aceptación — Error

| ID | Criterio | Resultado esperado |
|----|----------|--------------------|
| AC-005-E1 | Un usuario intenta autenticarse con credenciales incorrectas | El sistema rechaza con mensaje genérico sin revelar si el error es en usuario o contraseña |
| AC-005-E2 | Un usuario inactivo intenta autenticarse | El sistema rechaza la autenticación; el usuario no puede acceder al sistema |
| AC-005-E3 | Un token expirado se usa para acceder a un endpoint protegido | El sistema retorna HTTP 401; el usuario debe re-autenticarse |
| AC-005-E4 | Un token válido sin permiso para la operación solicitada accede a un endpoint restringido | El sistema retorna HTTP 403; la operación no se ejecuta; el estado del sistema no cambia |

---

## AC-006 — Generación y Exportación de Reportes

**Caso de uso / Capacidad:** CU-006 — Generar Reporte Gerencial (RF-015, RF-016)

**Bounded Context:** Reporting (BC-07)

**Regla de negocio asociada:** RN-009 (acceso restringido a reportería)

### Criterios de aceptación — Éxito

| ID | Criterio | Resultado esperado |
|----|----------|--------------------|
| AC-006-S1 | Un Gerente genera el reporte de stock actual con filtros de categoría y fecha | El reporte muestra todos los productos activos con su stock real al momento de la generación, aplicando los filtros indicados |
| AC-006-S2 | El Gerente descarga el reporte en formato XLSX | El archivo descargado preserva la misma estructura, filtros aplicados y datos que la vista en pantalla |
| AC-006-S3 | Un usuario con permiso explícito de auditoría genera el reporte auditoria-operaciones | El reporte muestra todos los registros del período con usuario, fecha, operación y valores antes/después |

### Criterios de aceptación — Error

| ID | Criterio | Resultado esperado |
|----|----------|--------------------|
| AC-006-E1 | Un usuario sin permiso de reportería intenta generar un reporte | El sistema rechaza con HTTP 403; el módulo de reportes no es accesible para ese rol |
| AC-006-E2 | El job ETL falla durante la generación del reporte | ReportRequest transiciona a estado Fallido; ReporteETLFallido (DE-021) registrado; usuario informado del error con opción de reintentar |

---

## AC-007 — Integración con Proveedor Externo (Saga-01)

**Caso de uso / Capacidad:** CU-008 — Integrar Proveedor Externo (RF-019)

**Bounded Context:** Integration (BC-09), Inventory (BC-03)

**Regla de negocio asociada:** RN-008 (proveedor activo), RN-010 (Kardex)

### Criterios de aceptación — Éxito

| ID | Criterio | Resultado esperado |
|----|----------|--------------------|
| AC-007-S1 | El sistema envía solicitud de reposición a un proveedor activo y el proveedor confirma | La entrada de inventario es registrada; el stock se actualiza; el resultado de integración queda en integration_logs |

### Criterios de aceptación — Error

| ID | Criterio | Resultado esperado |
|----|----------|--------------------|
| AC-007-E1 | El proveedor responde con error o supera el timeout de la integración (Saga-01 compensa) | SolicitudReposicionFallida (DE-018) emitido; si se había registrado una entrada parcial, EntradaRevertida (DE-019) emitido; el stock no queda en estado inconsistente; resultado registrado en integration_logs |
| AC-007-E2 | Se intenta integrar con un proveedor inactivo | El sistema rechaza la integración con mensaje de error al Administrador; no se inicia la solicitud |

---

## 10. Escenarios BDD

```gherkin
Feature: Registro de Entrada de Inventario
# Valida: AC-001

  # --- Escenario de éxito ---
  Scenario: Entrada válida incrementa stock y genera KardexRecord
    Given un Operador autenticado con permiso de registro de entradas
    And el Producto "PROD-001" está activo con stock actual de 50 unidades
    When el Operador registra una entrada de 30 unidades de "PROD-001" de tipo "Compra" con referencia "OC-2026-001"
    Then el stock de "PROD-001" se actualiza a 80 unidades de forma inmediata
    And se crea un KardexRecord con saldo de 80, tipo Entrada y referencia "OC-2026-001"
    And el movimiento es visible en el Kardex de "PROD-001"

  # --- Escenario de error: cantidad inválida ---
  Scenario: Entrada rechazada por cantidad igual a cero
    Given un Operador autenticado con permiso de registro de entradas
    And el Producto "PROD-001" está activo con stock actual de 50 unidades
    When el Operador intenta registrar una entrada de 0 unidades de "PROD-001"
    Then el sistema rechaza la operación con mensaje de validación de cantidad
    And el stock de "PROD-001" permanece en 50 unidades
    And no se crea ningún KardexRecord

  # --- Escenario de error: producto inactivo ---
  Scenario: Entrada rechazada porque el producto está inactivo
    Given un Operador autenticado con permiso de registro de entradas
    And el Producto "PROD-INACT-001" está inactivo en el catálogo
    When el Operador busca "PROD-INACT-001" para registrar una entrada
    Then el producto no aparece en la lista de productos disponibles para movimientos
    And no se puede iniciar el registro de entrada para ese producto
```

```gherkin
Feature: Registro de Salida de Inventario
# Valida: AC-002

  # --- Escenario de éxito ---
  Scenario: Salida válida reduce stock y activa AlertaBajoStock
    Given un Operador autenticado con permiso de registro de salidas
    And el Producto "PROD-002" está activo con stock actual de 10 unidades y stock mínimo de 8 unidades
    When el Operador registra una salida de 3 unidades de "PROD-002" de tipo "Venta" con referencia "VTA-2026-050"
    Then el stock de "PROD-002" se actualiza a 7 unidades de forma inmediata
    And se crea un KardexRecord con saldo de 7 y tipo Salida
    And se genera una AlertaBajoStock para "PROD-002" visible en el dashboard
    And se envía notificación al canal de alertas configurado

  # --- Escenario de error: stock insuficiente ---
  Scenario: Salida rechazada por stock insuficiente
    Given un Operador autenticado con permiso de registro de salidas
    And el Producto "PROD-002" está activo con stock actual de 5 unidades
    When el Operador intenta registrar una salida de 10 unidades de "PROD-002"
    Then el sistema rechaza la operación indicando que el stock disponible es de 5 unidades
    And el stock de "PROD-002" permanece en 5 unidades
    And no se crea ningún KardexRecord
```

```gherkin
Feature: Registro y Aprobación de Ajuste de Inventario
# Valida: AC-003

  # --- Escenario de éxito: ciclo completo aprobado ---
  Scenario: Ajuste aprobado por Supervisor actualiza el stock
    Given un Operador autenticado con permiso de creación de ajustes
    And el Producto "PROD-003" está activo con stock actual de 100 unidades
    When el Operador registra un ajuste de -5 unidades de "PROD-003" con motivo "Merma por deterioro"
    Then el AdjustmentRequest queda en estado Pendiente
    And el stock de "PROD-003" sigue siendo 100 unidades
    And el Supervisor recibe notificación de ajuste pendiente
    When el Supervisor aprueba el ajuste
    Then el stock de "PROD-003" se actualiza a 95 unidades
    And se crea un KardexRecord con saldo de 95 y tipo Ajuste
    And el AdjustmentRequest queda en estado Aprobado

  # --- Escenario de error: ajuste sin motivo ---
  Scenario: Creación de ajuste rechazada por campo motivo vacío
    Given un Operador autenticado con permiso de creación de ajustes
    And el Producto "PROD-003" está activo
    When el Operador intenta registrar un ajuste sin ingresar motivo
    Then el sistema rechaza la operación indicando que el motivo es obligatorio
    And no se crea ningún AdjustmentRequest
    And el stock de "PROD-003" no cambia

  # --- Escenario de error: compensación de Saga-02 ---
  Scenario: Fallo en actualización de stock revierte el ajuste aprobado
    Given el AdjustmentRequest "ADJ-100" está en estado Pendiente para "PROD-003"
    And el Supervisor aprueba el ajuste "ADJ-100"
    When la actualización del stock en Inventory falla por error del sistema
    Then el coordinador de Saga-02 emite AjusteRevertido
    And "ADJ-100" queda en estado Error
    And el stock de "PROD-003" no refleja el ajuste
    And el evento de compensación queda registrado en auditoría
```

```gherkin
Feature: Alertas Automáticas de Stock
# Valida: AC-004

  # --- Escenario de éxito ---
  Scenario: AlertaBajoStock generada y notificación enviada tras salida
    Given el Producto "PROD-004" tiene stock mínimo configurado en 10 unidades y stock actual de 12 unidades
    And el canal de notificaciones está disponible
    When se registra una salida de 3 unidades de "PROD-004"
    Then el stock de "PROD-004" se actualiza a 9 unidades
    And se genera una AlertaBajoStock para "PROD-004"
    And se envía notificación al canal de alertas configurado
    And la alerta es visible en el dashboard con tipo BajoStock

  # --- Escenario de error: servicio de notificación no disponible ---
  Scenario: Alerta registrada en sistema aunque el servicio de notificación falle
    Given el Producto "PROD-004" tiene stock mínimo de 10 unidades y stock actual de 12 unidades
    And el servicio de notificaciones externo no está disponible
    When se registra una salida de 3 unidades de "PROD-004"
    Then se genera la AlertaBajoStock y queda registrada en el sistema
    And el intento de notificación fallido queda registrado en notification_dispatch como NotificacionFallida
    And el sistema programa reintento con backoff exponencial
    And la alerta es visible en el dashboard independientemente del fallo de notificación
```

```gherkin
Feature: Autenticación y Control de Acceso (RBAC)
# Valida: AC-005

  # --- Escenario de éxito ---
  Scenario: Usuario activo se autentica con credenciales válidas y accede según su rol
    Given el usuario "operador1@controlstock.com" está registrado, activo y tiene rol Operador
    When el usuario ingresa sus credenciales válidas en el sistema
    Then el sistema emite un token JWT válido
    And el usuario accede al módulo de inventario
    And los módulos de administración y reportería gerencial no son accesibles para ese rol

  # --- Escenario de error: credenciales incorrectas ---
  Scenario: Rechazo de autenticación con contraseña incorrecta
    Given el usuario "operador1@controlstock.com" está registrado y activo
    When el usuario ingresa una contraseña incorrecta
    Then el sistema rechaza la autenticación
    And el mensaje de error no revela si el fallo es en usuario o contraseña
    And no se emite ningún token

  # --- Escenario de error: permiso insuficiente ---
  Scenario: Operador denegado al intentar aprobar un ajuste
    Given un Operador autenticado con token JWT válido sin permiso de aprobación
    When el Operador intenta ejecutar la aprobación de un AdjustmentRequest vía API
    Then el sistema retorna HTTP 403
    And el AdjustmentRequest permanece en estado Pendiente
    And se registra el intento denegado en auditoría
```

```gherkin
Feature: Generación y Exportación de Reportes
# Valida: AC-006

  # --- Escenario de éxito ---
  Scenario: Gerente genera y descarga reporte de stock actual en XLSX
    Given un Gerente autenticado con permiso de reportería
    And existen productos activos en el sistema con stock registrado en el read model
    When el Gerente selecciona el reporte "stock-actual" con filtro de categoría "Electrónicos"
    And descarga el reporte en formato XLSX
    Then el sistema genera el reporte con todos los productos activos de la categoría
    And el archivo XLSX contiene los mismos datos que la vista en pantalla
    And los datos reflejan el stock al momento de la generación del reporte

  # --- Escenario de error: fallo del ETL ---
  Scenario: Usuario informado cuando el ETL falla durante la generación
    Given un Gerente autenticado con permiso de reportería
    When el Gerente solicita el reporte "auditoria-operaciones"
    And el job ETL falla durante la extracción de datos
    Then el ReportRequest queda en estado Fallido
    And el usuario recibe mensaje de error con opción de reintentar
    And el evento ReporteETLFallido queda registrado en auditoría
```

```gherkin
Feature: Integración con Proveedor Externo — Reposición de Inventario (Saga-01)
# Valida: AC-007

  # --- Escenario de éxito ---
  Scenario: Reposición completada exitosamente actualiza el stock
    Given el Proveedor "PROV-001" está activo con configuración de integración REST válida en Vault
    And el Producto "PROD-005" tiene stock actual de 5 unidades
    When el sistema envía una solicitud de reposición de 50 unidades al proveedor "PROV-001"
    And el proveedor confirma la solicitud exitosamente
    Then el sistema registra una Entrada de 50 unidades de "PROD-005"
    And el stock de "PROD-005" se actualiza a 55 unidades
    And el resultado de integración queda registrado en integration_logs

  # --- Escenario de error: proveedor no responde — compensación de Saga-01 ---
  Scenario: Compensación de Saga-01 ante timeout del proveedor
    Given el Proveedor "PROV-001" está activo con configuración REST válida
    And el Producto "PROD-005" tiene stock actual de 5 unidades
    When el sistema envía la solicitud de reposición al proveedor
    And el proveedor no responde dentro del timeout configurado
    Then el sistema emite SolicitudReposicionFallida
    And si se había registrado una entrada parcial se emite EntradaRevertida
    And el stock de "PROD-005" no queda en estado inconsistente
    And el fallo queda registrado en integration_logs
```

---

*Generado como parte del Strategic Design del SDLC — ControlStock.*
*Documentos complementarios: `SDD-ControlStock-security.md` · `SDD-ControlStock-architecture.md`*
