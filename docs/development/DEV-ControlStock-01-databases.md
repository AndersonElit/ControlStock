# Etapa 1 — Bases de Datos y Migraciones

---

## 0. Automatización

Esta etapa se ejecuta mediante un único script que crea todas las bases de datos necesarias de forma automatizada:

```bash
bash .claude/scripts/init-databases.sh \
  -P controlstock \
  -p controlstock \
  -m controlstock \
  -u controlstock_app \
  -w <contraseña-segura>
```

### Qué hace el script

El script `init-databases.sh` conecta al servidor PostgreSQL en `postgresql.data.svc.cluster.local:5432` y al servidor MongoDB en `mongo.data.svc.cluster.local:27017`, ambos desplegados en el namespace `data` de K3s durante la Etapa 0.

**Para cada microservicio con adaptador PostgreSQL** (todos los servicios):

1. Crea la base de datos `controlstock_<svc_slug>` con owner `controlstock_app`
2. Crea el usuario `controlstock_app` si no existe (primera ejecución)
3. Otorga permisos `CONNECT`, `CREATE`, `USAGE` sobre la base de datos
4. Configura el esquema `public` con permisos para el usuario de aplicación

**Para cada microservicio con adaptador MongoDB** (catalog-service, inventory-service, supplier-service, y la read model compartida):

1. Crea la base de datos `controlstock_<svc_slug>` en MongoDB
2. Crea el usuario `controlstock_app` con rol `readWrite` restringido únicamente a esa base de datos
3. Para la read model: crea `controlstock_readmodel` con las collections vacías y sus validadores JSON Schema

**Lo que NO hace el script:**

- **No aplica `schema.sql` globalmente.** El DDL de cada bounded context es gestionado exclusivamente por Liquibase mediante changelogs versionados. Esto garantiza trazabilidad de todos los cambios de esquema.
- No crea índices de MongoDB (los índices se crean en la primera ejecución de los servicios vía colecciones de configuración).
- No configura replicación ni backups (gestionados por el módulo Terraform `helm-data`).

Las secciones siguientes constituyen **documentación de referencia de diseño** para entender la estructura de datos del sistema.

---

## 1. Objetivo

Crear bases de datos **aisladas por microservicio** siguiendo el patrón **Database-per-Service**, garantizando:

- **Acoplamiento cero** entre bounded contexts a nivel de datos: ningún servicio accede directamente a la base de datos de otro
- **Evolución independiente** del esquema de cada servicio sin afectar a los demás
- **Resiliencia** ante fallos de base de datos de un servicio sin propagación a otros
- **Independencia tecnológica**: cada servicio puede cambiar su motor de base de datos en el futuro sin impacto sistémico

La convención de nomenclatura establecida para todo el proyecto es `controlstock_<svc_slug>`, donde `<svc_slug>` es el nombre del servicio en minúsculas sin sufijos adicionales (ej. `iam`, `catalog`, `inventory`).

---

## 2. Estrategia de Persistencia

### Database-per-Service

Cada bounded context del proyecto ControlStock es propietario exclusivo de su base de datos. Esta regla es inviolable: ningún servicio realiza queries directas sobre la base de datos de otro servicio. La comunicación entre servicios se realiza exclusivamente mediante:

- **Eventos de dominio** publicados en Apache Kafka (patrón Transactional Outbox)
- **APIs REST** a través de Kong API Gateway

### Nomenclatura

| Patrón | Ejemplo |
|---|---|
| `controlstock_<svc_slug>` (PostgreSQL) | `controlstock_iam`, `controlstock_catalog` |
| `controlstock_<svc_slug>` (MongoDB) | `controlstock_catalog` (write model, no usado) |
| `controlstock_readmodel` (MongoDB shared) | Colecciones por proyector: stock, movimientos, kardex, productos, proveedores |

### Persistencia Políglota

ControlStock utiliza un enfoque de **persistencia políglota** que refleja los diferentes patrones de acceso a datos de cada bounded context:

| Motor | Rol | Servicios |
|---|---|---|
| **PostgreSQL 16** | Lado de comandos (Command Side) — transaccional ACID, fuente de verdad | Todos los microservicios (BC-01 al BC-09) |
| **MongoDB 7** | Lado de lectura (Read Model) — proyecciones optimizadas para consultas y ETL | inventory-service (stock, movimientos, kardex), catalog-service (productos), supplier-service (proveedores) |

El lado de lectura MongoDB (`controlstock_readmodel`) es actualizado por los propios microservicios productores como consumidores internos de sus propios eventos Kafka. **No existe un projection-service separado**; cada servicio con colección en MongoDB embebe el lógica de proyección en su propio módulo de infraestructura.

Los documentos de referencia del diseño de datos son:
- `docs/design/database/SDD-ControlStock-schema.sql` — DDL completo PostgreSQL por bounded context
- `docs/design/database/SDD-ControlStock-collections.js` — Definición de colecciones MongoDB con validadores JSON Schema

---

## 3. PostgreSQL — Esquema Relacional

### Referencia de Diseño

El DDL completo, incluyendo tipos de datos precisos, constraints, índices y comentarios de columna, se encuentra en:

```
docs/design/database/SDD-ControlStock-schema.sql
```

Este archivo está organizado por bounded context con etiquetas `-- BC-XX` que el scaffold utiliza para extraer los bloques relevantes y generar los changelogs Liquibase iniciales de cada servicio.

### Bounded Contexts y sus Tablas

| Bounded Context | Base de Datos Propietaria | Tablas |
|---|---|---|
| IAM (BC-01) | `controlstock_iam` | `roles`, `permisos`, `rol_permisos`, `usuarios`, `usuario_roles` |
| Catalog (BC-02) | `controlstock_catalog` | `categorias`, `productos`, `outbox` |
| Inventory (BC-03) | `controlstock_inventory` | `stock_levels`, `inventory_movements`, `outbox`, `processed_message` |
| Adjustment (BC-04) | `controlstock_adjustment` | `adjustment_requests`, `adjustment_decisions`, `outbox`, `processed_message` |
| Alert (BC-05) | `controlstock_alert` | `alert_rules`, `alert_events` |
| Supplier (BC-06) | `controlstock_supplier` | `suppliers`, `integration_configs` |
| Reporting (BC-07) | `controlstock_reporting` | `report_schema_catalog`, `report_requests`, `report_files` |
| Audit (BC-08) | `controlstock_audit` | `audit_log` |
| Integration (BC-09) | `controlstock_integration` | `integration_logs`, `notification_dispatch`, `saga_instance`, `saga_step_log`, `outbox`, `processed_message` |

### Notas de Diseño por Bounded Context

**IAM (controlstock_iam):** Define el modelo de autorización basado en roles y permisos. La tabla `usuarios` almacena únicamente el `keycloak_subject_id` como FK externa, delegando la autenticación completamente a Keycloak. No almacena contraseñas.

**Catalog y Supplier (controlstock_catalog, controlstock_supplier):** Incluyen tabla `outbox` para el patrón Transactional Outbox. Los eventos se escriben en la misma transacción que la mutación de dominio y son leídos por el Outbox Poller para publicación en Kafka.

**Inventory (controlstock_inventory):** Incluye `outbox` (productor) y `processed_message` (consumidor idempotente para eventos `AjusteAprobado` provenientes de adjustment-service). La tabla `stock_levels` es la fuente de verdad para el stock actual por producto y almacén.

**Adjustment (controlstock_adjustment):** Incluye tablas de solicitud y decisión de ajuste. El campo `processed_message` garantiza idempotencia en la recepción de comandos externos.

**Integration (controlstock_integration):** Es el bounded context más complejo. Gestiona el orchestrador LRA (`saga_instance`, `saga_step_log`), el log de integraciones con sistemas externos (`integration_logs`) y el despacho de notificaciones (`notification_dispatch`). Participa como coordinador del saga `reposicion-inventario`.

**Reporting (controlstock_reporting):** La tabla `report_schema_catalog` actúa como catálogo de metadatos que el ETL Spark consulta para conocer los tipos de reporte disponibles, sus plantillas y destinos en MinIO. `report_requests` rastrea el estado de cada solicitud de reporte.

---

## 4. PostgreSQL — Changelogs Liquibase por Microservicio

### Repositorio de Migraciones

Los changelogs Liquibase residen en el repositorio Git **`controlstock-migrations`** alojado en Gitea:

```
http://<VPS_IP>:3000/controlstock/controlstock-migrations
```

Este repositorio es **generado automáticamente** por el step 6b del scaffold (`scaffold-all-services.sh`), que:

1. Extrae el bloque DDL de cada bounded context desde `SDD-ControlStock-schema.sql`
2. Convierte cada bloque a formato YAML Liquibase
3. Genera el changelog maestro `root.yaml` por servicio
4. Crea el repositorio en Gitea y hace push del contenido inicial

**Estructura local** (antes del push a Gitea), generada en el workspace de trabajo:

```
db/
├── iam-service/
│   └── changelog/
│       ├── root.yaml
│       ├── 00001_initial_schema.yaml
│       └── 00002_seed_roles.yaml
├── catalog-service/
│   └── changelog/
│       ├── root.yaml
│       └── 00001_initial_schema.yaml
├── inventory-service/
│   └── changelog/
│       ├── root.yaml
│       └── 00001_initial_schema.yaml
├── adjustment-service/
│   └── changelog/
│       ├── root.yaml
│       └── 00001_initial_schema.yaml
├── alert-service/
│   └── changelog/
│       ├── root.yaml
│       └── 00001_initial_schema.yaml
├── supplier-service/
│   └── changelog/
│       ├── root.yaml
│       └── 00001_initial_schema.yaml
├── report-service/
│   └── changelog/
│       ├── root.yaml
│       └── 00001_initial_schema.yaml
├── audit-service/
│   └── changelog/
│       ├── root.yaml
│       └── 00001_initial_schema.yaml
└── integration-service/
    └── changelog/
        ├── root.yaml
        └── 00001_initial_schema.yaml
```

### Convención de Nomenclatura de Archivos

- Formato de numeración: `00001_<descripcion_snake_case>.yaml`
- El número es secuencial de 5 dígitos con ceros a la izquierda
- La descripción usa snake_case y describe el cambio en términos de negocio
- El changelog maestro siempre se llama `root.yaml` e incluye todos los archivos en orden

Ejemplo de `root.yaml`:

```yaml
databaseChangeLog:
  - include:
      file: 00001_initial_schema.yaml
      relativeToChangelogFile: true
  - include:
      file: 00002_seed_roles.yaml
      relativeToChangelogFile: true
```

### Changelogs por Microservicio

| Servicio | Base de Datos | Changelogs |
|---|---|---|
| iam-service | controlstock_iam | `00001_initial_schema.yaml`, `00002_seed_roles.yaml` |
| catalog-service | controlstock_catalog | `00001_initial_schema.yaml` |
| inventory-service | controlstock_inventory | `00001_initial_schema.yaml` |
| adjustment-service | controlstock_adjustment | `00001_initial_schema.yaml` |
| alert-service | controlstock_alert | `00001_initial_schema.yaml` |
| supplier-service | controlstock_supplier | `00001_initial_schema.yaml` |
| report-service | controlstock_reporting | `00001_initial_schema.yaml` |
| audit-service | controlstock_audit | `00001_initial_schema.yaml` |
| integration-service | controlstock_integration | `00001_initial_schema.yaml` |

### Aplicación de Migraciones

Las migraciones se aplican mediante el script `run-liquibase-migrations.sh` con la opción `--gitea-clone`, que clona el repositorio `controlstock-migrations` desde Gitea y ejecuta Liquibase contra cada base de datos:

```bash
bash .claude/scripts/run-liquibase-migrations.sh \
  --gitea-url http://<VPS_IP>:3000 \
  --gitea-clone \
  --pg-host postgresql.data.svc.cluster.local \
  --pg-port 5432 \
  --pg-user controlstock_app \
  --pg-password <contraseña-segura> \
  --prefix controlstock
```

**Regla de propiedad:** Cada tabla de la base de datos es propiedad exclusiva de exactamente un microservicio. Esta regla es controlada mediante revisiones de código (PR review) en el repositorio `controlstock-migrations`.

**Liquibase en producción:** Los microservicios Spring Boot están configurados con `spring.liquibase.enabled=false` en producción. Las migraciones se ejecutan desde un Job de Kubernetes dedicado (`liquibase-migration-job`) antes del despliegue ArgoCD, garantizando que el esquema esté actualizado antes de que los pods del servicio inicien.

---

## 5. MongoDB — Colecciones y Validadores

### Referencia de Diseño

La definición completa de colecciones, validadores JSON Schema e índices se encuentra en:

```
docs/design/database/SDD-ControlStock-collections.js
```

Este archivo contiene scripts `db.createCollection()` con validadores de esquema y comandos `db.<collection>.createIndex()` que se ejecutan durante la inicialización del entorno.

### Read Model Compartido: controlstock_readmodel

Todas las colecciones de lectura de ControlStock residen en una única base de datos MongoDB `controlstock_readmodel`. Este diseño centraliza las proyecciones de lectura optimizando las consultas del dashboard y el acceso del ETL Spark.

| Colección | Base de Datos | Servicio Escritor | Propósito |
|---|---|---|---|
| `stock` | `controlstock_readmodel` | inventory-service | Estado actual de stock por producto y almacén, optimizado para el dashboard de inventario en tiempo real |
| `movimientos` | `controlstock_readmodel` | inventory-service | Proyección del histórico de movimientos de inventario; fuente primaria del ETL Spark para el reporte `movimientos-periodo` |
| `kardex` | `controlstock_readmodel` | inventory-service | Vista Kardex con array de entradas y salidas por producto; utilizado para el reporte `kardex` y auditorías manuales |
| `productos` | `controlstock_readmodel` | catalog-service | Proyección del catálogo de productos activos e inactivos; fuente del ETL para el reporte `stock-actual` y enriquecimiento de datos |
| `proveedores` | `controlstock_readmodel` | supplier-service | Proyección de proveedores con configuración de integración; fuente del ETL para el reporte `proveedores-actividad` |

### Patrón de Proyección

Los proyectores son **consumidores Kafka embebidos dentro de cada microservicio productor**, no servicios separados:

- `inventory-service` consume sus propios eventos `StockActualizado`, `EntradaRegistrada`, `SalidaRegistrada` para actualizar `stock`, `movimientos` y `kardex`
- `catalog-service` consume sus propios eventos `ProductoCreado`, `ProductoActualizado`, `ProductoInactivado` para actualizar `productos`
- `supplier-service` consume sus propios eventos `ProveedorActualizado` para actualizar `proveedores`

Esta arquitectura evita la doble latencia del consumo inter-servicio y mantiene la consistencia de la proyección dentro del mismo límite transaccional del servicio.

### Flujo de Datos hacia el ETL

```
PostgreSQL (fuente de verdad)
    │
    ▼ eventos Kafka (outbox)
MongoDB controlstock_readmodel (read model)
    │
    ▼ Spark MongoDB Connector (lectura primaria ETL)
MinIO (archivos Parquet)
    │
    ▼ OpenFaaS report-format-consumer
MinIO (XLSX / CSV / PDF finales)
```

El ETL Spark (`report-etl-service`) utiliza MongoDB como **fuente de datos primaria** mediante el conector oficial Spark-MongoDB, complementado con acceso JDBC a `controlstock_reporting` (para metadatos de esquema) y `controlstock_audit` (para datos del reporte de auditoría).

### Accesos MongoDB por Servicio

| Servicio | Base de Datos MongoDB | Operaciones |
|---|---|---|
| inventory-service | `controlstock_readmodel` | Write (upsert en `stock`, `movimientos`, `kardex`) |
| catalog-service | `controlstock_readmodel` | Write (upsert en `productos`) |
| supplier-service | `controlstock_readmodel` | Write (upsert en `proveedores`) |
| report-etl-service (Spark) | `controlstock_readmodel` | Read (scan de `stock`, `movimientos`, `kardex`, `productos`, `proveedores`) |

---

## 6. Criterios de Aceptación

### Automatización

- [ ] `init-databases.sh` con parámetros `-P controlstock -p controlstock -m controlstock -u controlstock_app -w <clave>` finaliza con exit code 0 mostrando confirmación `✓` para cada base de datos creada
- [ ] Cada microservicio tiene su propia base de datos PostgreSQL aislada: ninguna tabla es compartida entre bases de datos de diferentes servicios
- [ ] El usuario `controlstock_app` tiene permisos `CONNECT` y `CREATE` únicamente sobre las bases de datos de ControlStock

### PostgreSQL

- [ ] `psql -U controlstock_app -l | grep controlstock` lista exactamente 9 bases de datos (una por bounded context)
- [ ] Conexión a `controlstock_iam` desde `psql` como `controlstock_app` es exitosa
- [ ] Conexión cruzada (ej. `controlstock_app` intentando conectar a `postgres` por defecto) es denegada por política de roles
- [ ] La tabla `databasechangelog` de Liquibase existe en cada base de datos tras la aplicación de migraciones

### MongoDB

- [ ] `mongo controlstock_readmodel --eval "db.getCollectionNames()"` retorna `['kardex', 'movimientos', 'productos', 'proveedores', 'stock']`
- [ ] El usuario `controlstock_app` puede escribir en `controlstock_readmodel` pero no en bases de datos de otros proyectos
- [ ] Los validadores JSON Schema están activos: insertar un documento con estructura inválida retorna `WriteError`
- [ ] `db.stock.getIndexes()` muestra el índice compuesto `{producto_id: 1, almacen_id: 1}` como único

### Changelogs Liquibase

- [ ] El repositorio `controlstock-migrations` existe y es accesible en `http://<VPS_IP>:3000/controlstock/controlstock-migrations`
- [ ] Cada servicio tiene su directorio `db/<servicio>/changelog/` con al menos `root.yaml` y `00001_initial_schema.yaml`
- [ ] `iam-service` tiene `00002_seed_roles.yaml` con los 7 roles del sistema
- [ ] `run-liquibase-migrations.sh --gitea-clone` aplica todas las migraciones sin errores de checksum
- [ ] Tras aplicar migraciones: `select count(*) from roles` en `controlstock_iam` retorna 7 (Administrador, Supervisor, Operador, Gerente, Analista, Auditor, APIConsumer)
