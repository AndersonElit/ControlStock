# Etapa 3j — Microservicio: Report ETL Service (BC-07 — Batch)

## Job Spark CronJob — Extracción + Validación + Transformación de Reportes

## Tabla de Contenidos

1. [Contexto y Responsabilidad](#contexto-y-responsabilidad)
2. [Prerrequisitos](#prerrequisitos)
3. [Ciclo de Desarrollo — Batch Spark en K3s](#ciclo-de-desarrollo--batch-spark-en-k3s)
4. [Capa de Dominio (Scala)](#capa-de-dominio-scala)
5. [Capa de Aplicación (Scala)](#capa-de-aplicación-scala)
6. [Capa de Infraestructura (Spark)](#capa-de-infraestructura-spark)
7. [CronJob Deployment](#cronjob-deployment)
8. [Especificación TDD — sbt test](#especificación-tdd--sbt-test)
9. [Criterios de Aceptación](#criterios-de-aceptación)

---

## Contexto y Responsabilidad

El **Report ETL Service** (Bounded Context BC-07 — Batch) es el componente Spark/Scala responsable de extraer, validar, transformar y persistir los datos de reportes en ControlStock. Es el **décimo componente en implementarse** y es fundamentalmente diferente al resto del sistema: no es un microservicio REST ni un Deployment Kubernetes. Es un **CronJob Kubernetes** que ejecuta un job Spark de vida corta, procesa un lote de datos y termina.

### Naturaleza del componente

| Característica | Valor |
|---------------|-------|
| **Tipo** | Apache Spark Job (Scala, sbt) |
| **Generación de scaffold** | `scala_hexagonal_scaffold.py` (NO maven scaffold) |
| **Build** | `sbt compile` + `sbt assembly` (fat JAR) |
| **Deployment** | Kubernetes CronJob (NO Deployment, NO Service) |
| **CI/CD** | Jenkins pipeline termina en `bumpImageTag`; ArgoCD sincroniza el CronJob |
| **Smoke tests en CI** | NO — CronJob no tiene endpoint HTTP; el CI no ejecuta pruebas de humo post-deploy |
| **Trigger** | Diario a las 2 AM (`0 2 * * *`) O bajo demanda vía Kafka consumer |
| **Duración típica** | 5–15 minutos por ejecución |

### Responsabilidades del componente

| Responsabilidad | Descripción |
|----------------|-------------|
| **Extracción de datos** | Leer colecciones MongoDB (`stock`, `movimientos`, `productos`, `proveedores`) via Spark MongoDB Connector; leer `audit_log` via Spark JDBC desde PostgreSQL |
| **Validación de esquema** | Comparar columnas del DataFrame extraído contra `report_schema_catalog` (leído de `controlstock_reporting` via JDBC); rechazar reportes con columnas faltantes o tipos incorrectos |
| **Transformación** | Aplicar `ReportTransformer` específico por tipo de reporte (Factory pattern DR-10): joins, aggregations, filtros de fecha |
| **Almacenamiento Parquet** | Escribir el DataFrame resultante como `.parquet` en MinIO bucket `controlstock-reports/parquet/{report_type}/{year}/{month}/{request_id}.parquet` |
| **Publicación de eventos** | Publicar `ReporteParquetGenerado` en topic `controlstock.reporting.parquet-generado` al finalizar exitosamente |
| **Notificación de fallo** | Publicar `ReporteETLFallido` en topic `controlstock.reporting.etl-fallido` si la validación de esquema o el procesamiento falla |
| **Modo dual de trigger** | Puede ejecutarse por CronJob schedule (procesa todos los tipos pendientes) O por solicitud específica vía Kafka (`controlstock.reporting.requests`) |

### Lo que el componente NO hace

| Restricción | Justificación |
|-------------|---------------|
| No expone endpoints HTTP | Es un job batch; no tiene controladores REST ni actuator |
| No mantiene base de datos propia | Lee de MongoDB y PostgreSQL existentes; no es propietario de ningún schema |
| No genera reportes en formatos finales (XLSX, CSV, PDF) | Solo produce Parquet; el `report-format-consumer` convierte Parquet al formato solicitado |
| No gestiona el ciclo de vida de `ReportRequest` | Esa responsabilidad pertenece a `report-service` (BC-07 REST) |
| No tiene bloqueo reactivo (no usa Project Reactor) | Es Spark/Scala; usa APIs de Dataset/DataFrame síncronas de Spark (diseñado para batch, no streaming reactivo) |

### Arquitectura general

```
┌────────────────────────────────────────────────────────────────────────────┐
│                   Report ETL Service (BC-07 — Batch)                       │
│                   Kubernetes CronJob: schedule "0 2 * * *"                 │
│                                                                            │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                    Apache Spark Job (Scala)                         │   │
│  │                                                                     │   │
│  │  EntryPoint.main()                                                  │   │
│  │       │                                                             │   │
│  │       ▼                                                             │   │
│  │  ExtractReportUseCase.execute(reportType, params)                   │   │
│  │       │                                                             │   │
│  │       ├──► SourceDataPort ──► SparkMongoSourceAdapter              │   │
│  │       │                       (MongoDB: stock, movimientos,        │   │
│  │       │                        productos, proveedores)             │   │
│  │       │    SourceDataPort ──► SparkJdbcSourceAdapter               │   │
│  │       │                       (PostgreSQL: audit_log,              │   │
│  │       │                        report_schema_catalog)              │   │
│  │       │                                                             │   │
│  │       ├──► Validate schema against report_schema_catalog           │   │
│  │       │    (falla → ReporteETLFallido)                              │   │
│  │       │                                                             │   │
│  │       ├──► ReportTransformerFactory.get(reportType)                │   │
│  │       │    → ReportTransformer.transform(df, params)               │   │
│  │       │                                                             │   │
│  │       ├──► ParquetStorePort ──► SparkMinioParquetAdapter           │   │
│  │       │    (MinIO: controlstock-reports/parquet/...)               │   │
│  │       │                                                             │   │
│  │       └──► EventBusPort ──► KafkaEventPublisher                    │   │
│  │            (ReporteParquetGenerado o ReporteETLFallido)             │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
└────────────────────────────────────────────────────────────────────────────┘

Fuentes de datos:
  MongoDB controlstock_readmodel:
    stock       → stock-actual
    movimientos → movimientos-periodo
    productos   → (enriquecimiento en joins)
    proveedores → proveedores-actividad

  PostgreSQL controlstock_audit:
    audit_log   → auditoria-operaciones

  PostgreSQL controlstock_reporting:
    report_schema_catalog → validación de esquema (lectura)

Destino:
  MinIO: controlstock-reports/parquet/{report_type}/{year}/{month}/{request_id}.parquet

Kafka (produce):
  controlstock.reporting.parquet-generado  (ReporteParquetGenerado)
  controlstock.reporting.etl-fallido       (ReporteETLFallido)

Kafka (consume — trigger on-demand):
  controlstock.reporting.requests          (SolicitudReporteGenerada)
```

### Tipos de reporte (Factory DR-10)

| Tipo | Transformer | Fuente primaria | Descripción |
|------|------------|----------------|-------------|
| `stock-actual` | `StockActualReportTransformer` | MongoDB: `stock` + `productos` | Nivel actual de stock por producto con datos de catálogo |
| `movimientos-periodo` | `MovimientosPeriodoReportTransformer` | MongoDB: `movimientos` | Movimientos dentro de rango de fechas con tipo y cantidad |
| `auditoria-operaciones` | `AuditOperacionesReportTransformer` | PostgreSQL: `audit_log` | Registro de operaciones con usuario, acción y timestamp |
| `proveedores-actividad` | `ProveedoresActividadReportTransformer` | MongoDB: `proveedores` + `movimientos` | Actividad por proveedor: órdenes, volumen, últimas entradas |

---

## Prerrequisitos

| Prerrequisito | Documento de referencia | Verificación |
|--------------|------------------------|-------------|
| Etapa 0 — Infraestructura base | `DEV-ControlStock-00-infrastructure.md` | K3s corriendo; namespace `apps`, `databases`, `kafka` activos |
| Etapa 0c — Observabilidad | `DEV-ControlStock-0c-observability.md` | OTEL collector activo para recibir trazas del job Spark |
| Etapa 1 — Bases de datos | `DEV-ControlStock-01-databases.md` | MongoDB `controlstock_readmodel` con colecciones `stock`, `movimientos`, `productos`, `proveedores`; PostgreSQL `controlstock_audit.audit_log`; PostgreSQL `controlstock_reporting.report_schema_catalog` con seeds |
| Etapa 2 — Scaffold generado | `DEV-ControlStock-02-scaffold.md` | Proyecto Scala `report-etl-service` generado por `scala_hexagonal_scaffold.py`; `build.sbt` con dependencias Spark + MongoDB Connector + JDBC |
| Etapa 2b — Pipeline CI/CD | `DEV-ControlStack-02b-cicd.md` | Job `report-etl-service` en Jenkins; pipeline configura CronJob (no Deployment) |
| **Etapa 3g — Report Service corriendo** | `DEV-ControlStock-03-ms-report-service.md` | `report_schema_catalog` populado con los 4 tipos de reporte y sus ColumnSpec |
| **Etapa 3c — Inventory Service corriendo** | `DEV-ControlStock-03-ms-inventory-service.md` | MongoDB `controlstock_readmodel.stock` y `.movimientos` populadas vía proyección de inventory-service |
| **Etapa 3f — Supplier Service corriendo** | `DEV-ControlStock-03-ms-supplier-service.md` | MongoDB `controlstock_readmodel.proveedores` populada |
| **Etapa 3h — Audit Service corriendo** | `DEV-ControlStock-03-ms-audit-service.md` | PostgreSQL `controlstock_audit.audit_log` con datos de auditoría |
| MinIO corriendo | Etapa 0 | Bucket `controlstock-reports` creado; sub-path `parquet/` disponible; credenciales en Vault |
| Kafka (Strimzi KRaft) corriendo | Etapa 0 | Topics `controlstock.reporting.parquet-generado`, `controlstock.reporting.etl-fallido`, `controlstock.reporting.requests` creados |

### Nota sobre datos en MongoDB en desarrollo

El read model MongoDB es poblado por los servicios de dominio (inventory-service, supplier-service, catalog-service) vía sus Kafka consumers de proyección. En un entorno de desarrollo limpio, es necesario generar movimientos de prueba antes de ejecutar el ETL. Los comandos de verificación a continuación validan que hay datos suficientes para una ejecución no trivial.

### Verificación de prerrequisitos

```bash
# Verificar MongoDB read model — colecciones con datos
kubectl exec -n databases deploy/mongodb -- mongosh \
  --eval 'use controlstock_readmodel; print(JSON.stringify({
    stock: db.stock.countDocuments(),
    movimientos: db.movimientos.countDocuments(),
    productos: db.productos.countDocuments(),
    proveedores: db.proveedores.countDocuments()
  }))'
# Esperado: todos > 0

# Verificar audit_log en PostgreSQL
kubectl exec -n databases deploy/postgresql -- psql \
  -U controlstock_audit -d controlstock_audit \
  -c "SELECT COUNT(*) FROM audit_log;"
# Esperado: > 0

# Verificar report_schema_catalog con los 4 tipos
kubectl exec -n databases deploy/postgresql -- psql \
  -U controlstock_reporting -d controlstock_reporting \
  -c "SELECT report_type, array_length(column_specs, 1) AS num_columns
      FROM report_schema_catalog ORDER BY report_type;"
# Esperado: 4 filas con columnas definidas

# Verificar MinIO bucket y path
kubectl exec -n minio deploy/minio -- mc ls local/controlstock-reports/
# Debe mostrar el bucket (aunque vacío de parquet inicialmente)

# Verificar topics Kafka reporting
kubectl exec -n kafka deploy/kafka -- \
  kafka-topics.sh --list --bootstrap-server kafka:9092 \
  | grep "controlstock.reporting"
# Esperado:
# controlstock.reporting.etl-fallido
# controlstock.reporting.parquet-generado
# controlstock.reporting.requests

# Verificar Vault secretos para el ETL
kubectl exec -n infra deploy/vault -- \
  vault kv get secret/report-etl-service/minio
# Esperado: endpoint, access-key, secret-key

kubectl exec -n infra deploy/vault -- \
  vault kv get secret/report-etl-service/mongodb
# Esperado: uri (connection string)
```

---

## Ciclo de Desarrollo — Batch Spark en K3s

### Diferencias con microservicios REST

```
┌──────────────────────────────────────────────────────────────────────────────┐
│        Ciclo de Desarrollo — Report ETL Service (Spark CronJob)              │
│                                                                              │
│  DIFERENCIAS CLAVE vs. microservicio REST:                                   │
│  ✗ No hay /actuator/health — el job termina                                  │
│  ✗ No hay smoke tests automáticos post-deploy                                │
│  ✓ Verificación manual: kubectl create job --from=cronjob/...                │
│  ✓ CI pipeline termina en bumpImageTag                                       │
│                                                                              │
│  1. Escribir test RED (sbt test — falla esperada)                            │
│         │                                                                    │
│         ▼                                                                    │
│  2. Implementar mínimo código Scala GREEN                                    │
│         │  (UseCase / Transformer / Adapter)                                  │
│         ▼                                                                    │
│  3. REFACTOR — mejorar diseño sin romper tests                               │
│         │                                                                    │
│         ▼                                                                    │
│  4. sbt compile && sbt assembly                                              │
│         │  (genera fat JAR con spark-submit)                                 │
│         ▼                                                                    │
│  5. git push → Gitea webhook → Jenkins pipeline                              │
│         │  → docker build → push registry                                    │
│         │  → bumpImageTag en repo ArgoCD                                     │
│         ▼                                                                    │
│  6. ArgoCD sync → CronJob spec actualizado en K3s                            │
│         │                                                                    │
│         ▼                                                                    │
│  7. Ejecución manual de verificación en K3s:                                 │
│     kubectl create job --from=cronjob/report-etl-service \                  │
│       report-etl-manual-001 -n apps                                          │
│         │                                                                    │
│         ▼                                                                    │
│  8. kubectl logs -n apps job/report-etl-manual-001 -f                        │
│     → Verificar: "ReporteParquetGenerado publicado" en logs                  │
│     → Verificar: archivo .parquet en MinIO                                   │
│     → Verificar: evento en topic controlstock.reporting.parquet-generado     │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Orden de implementación incremental

| Incremento | Capa | Contenido | Condición de avance |
|-----------|------|-----------|-------------------|
| **I-1** | Dominio | Case classes: `ReportSchema`, `ColumnSpec`, `ReportType` (sealed trait/enum), `ReportParquetGenerated`, `ReportEtlFailed`; traits de puertos | `sbt compile` GREEN; tests de case class inmutabilidad GREEN |
| **I-2** | Dominio | Lógica de validación de esquema en `ReportSchema.validate(df)`: comparar columnas del DataFrame contra ColumnSpec; retornar `Right[Unit]` o `Left[SchemaValidationError]` | Tests unitarios de validación GREEN |
| **I-3** | Aplicación | `ReportTransformerFactory` con pattern matching sobre `ReportType`; `ReportTransformer` trait | Tests factory: tipo conocido → transformer correcto; tipo desconocido → `UnsupportedReportTypeException` GREEN |
| **I-4** | Aplicación | `StockActualReportTransformer` (join stock + productos) | Tests con SparkSession local (`master("local[1]")`) GREEN |
| **I-5** | Aplicación | `MovimientosPeriodoReportTransformer` (filter by date range) | Tests con SparkSession local GREEN |
| **I-6** | Aplicación | `AuditOperacionesReportTransformer` (JDBC source) | Tests con Testcontainers PostgreSQL GREEN |
| **I-7** | Aplicación | `ProveedoresActividadReportTransformer` (join proveedores + movimientos) | Tests con SparkSession local GREEN |
| **I-8** | Aplicación | `ExtractReportUseCase.execute()` completo: validación → factory → transform → store → publish | Tests de integración de aplicación con stubs de adapters GREEN |
| **I-9** | Infraestructura | `SparkMongoSourceAdapter` (Spark MongoDB Connector) | Tests con Testcontainers MongoDB GREEN |
| **I-10** | Infraestructura | `SparkJdbcSourceAdapter` (PostgreSQL JDBC) | Tests con Testcontainers PostgreSQL GREEN |
| **I-11** | Infraestructura | `SparkMinioParquetAdapter` (write + read round-trip) | Tests con Testcontainers MinIO GREEN |
| **I-12** | Infraestructura | `KafkaEventPublisher` (produce `ReporteParquetGenerado` y `ReporteETLFallido`) | Tests con embedded Kafka GREEN |
| **I-13** | EntryPoint | `EntryPoint.main()` con Kafka consumer para trigger on-demand + modo CronJob | `sbt assembly` GREEN; ejecución manual en K3s GREEN |

---

## Capa de Dominio (Scala)

### Regla: sin Spark, sin JDBC, sin Kafka en el dominio

El dominio Scala no importa ningún tipo de Spark (`Dataset`, `DataFrame`, `SparkSession`), ni tipos JDBC, ni clientes Kafka. Solo tipos Scala estándar, case classes, sealed traits y tipos algebraicos. Los DataFrames se manejan en la capa de infraestructura y los resultados se abstraen en tipos de dominio.

### Tipos de dominio

```scala
// src/main/scala/com/controlstock/reporting/etl/domain/model/ReportType.scala
sealed trait ReportType {
  def value: String
}

object ReportType {
  case object StockActual           extends ReportType { val value = "stock-actual" }
  case object MovimientosPeriodo    extends ReportType { val value = "movimientos-periodo" }
  case object AuditoriaOperaciones  extends ReportType { val value = "auditoria-operaciones" }
  case object ProveedoresActividad  extends ReportType { val value = "proveedores-actividad" }

  def fromString(s: String): Either[String, ReportType] = s match {
    case "stock-actual"           => Right(StockActual)
    case "movimientos-periodo"    => Right(MovimientosPeriodo)
    case "auditoria-operaciones"  => Right(AuditoriaOperaciones)
    case "proveedores-actividad"  => Right(ProveedoresActividad)
    case unknown                  => Left(s"Tipo de reporte desconocido: $unknown")
  }

  val all: Seq[ReportType] =
    Seq(StockActual, MovimientosPeriodo, AuditoriaOperaciones, ProveedoresActividad)
}
```

```scala
// src/main/scala/com/controlstock/reporting/etl/domain/model/ColumnSpec.scala
/**
 * Especificación de una columna del reporte: nombre y tipo esperado.
 * Los tipos siguen la nomenclatura de Spark SQL para facilitar la validación.
 */
final case class ColumnSpec(
  name: String,
  dataType: String,  // "StringType", "LongType", "DoubleType", "TimestampType", etc.
  nullable: Boolean = true
)
```

```scala
// src/main/scala/com/controlstock/reporting/etl/domain/model/ReportSchema.scala
/**
 * Esquema de un tipo de reporte: conjunto de ColumnSpec esperadas.
 * Leído desde report_schema_catalog al inicio de cada ejecución.
 */
final case class ReportSchema(
  reportType: ReportType,
  columns: Seq[ColumnSpec]
) {
  /**
   * Valida que las columnas presentes en el esquema Spark (structFields)
   * coincidan con las ColumnSpec definidas en el catálogo.
   *
   * @param presentColumns mapa nombre → tipo (extraído del DataFrame.schema en infraestructura)
   * @return Right(()) si la validación pasa; Left(SchemaValidationError) con detalle del fallo
   */
  def validate(presentColumns: Map[String, String]): Either[SchemaValidationError, Unit] = {
    val missingColumns = columns.filterNot(spec => presentColumns.contains(spec.name))
    val wrongTypeColumns = columns.filter { spec =>
      presentColumns.get(spec.name).exists(_ != spec.dataType)
    }

    if (missingColumns.nonEmpty || wrongTypeColumns.nonEmpty) {
      Left(SchemaValidationError(
        reportType = reportType,
        missingColumns = missingColumns.map(_.name),
        wrongTypeColumns = wrongTypeColumns.map(s =>
          s"${s.name}: esperado=${s.dataType}, encontrado=${presentColumns.getOrElse(s.name, "N/A")}")
      ))
    } else {
      Right(())
    }
  }
}
```

```scala
// src/main/scala/com/controlstock/reporting/etl/domain/model/ReportParquetGenerated.scala
/**
 * Evento de dominio: reporte Parquet generado exitosamente y subido a MinIO.
 */
final case class ReportParquetGenerated(
  requestId: String,
  reportType: ReportType,
  parquetPath: String,    // path completo en MinIO, e.g. "parquet/stock-actual/2025/01/req-001.parquet"
  rowCount: Long,
  generatedAt: java.time.Instant
)
```

```scala
// src/main/scala/com/controlstock/reporting/etl/domain/model/ReportEtlFailed.scala
/**
 * Evento de dominio: fallo en el proceso ETL.
 * Consumido por report-service para marcar el ReportRequest como FALLIDO.
 */
final case class ReportEtlFailed(
  requestId: String,
  reportType: ReportType,
  reason: String,
  failedAt: java.time.Instant
)
```

```scala
// src/main/scala/com/controlstock/reporting/etl/domain/model/SchemaValidationError.scala
final case class SchemaValidationError(
  reportType: ReportType,
  missingColumns: Seq[String],
  wrongTypeColumns: Seq[String]
) {
  def toMessage: String = {
    val missing  = if (missingColumns.nonEmpty)
      s"columnas faltantes: ${missingColumns.mkString(", ")}" else ""
    val wrongType = if (wrongTypeColumns.nonEmpty)
      s"tipos incorrectos: ${wrongTypeColumns.mkString("; ")}" else ""
    s"Validación de esquema fallida para ${reportType.value}. $missing $wrongType".trim
  }
}
```

### Puertos (traits de dominio)

```scala
// src/main/scala/com/controlstock/reporting/etl/domain/port/out/SourceDataPort.scala
/**
 * Puerto de entrada de datos: abstrae MongoDB y JDBC.
 * La implementación retorna un mapa de columna→tipo y los datos como tipo opaco.
 * El uso de Any permite que el dominio no importe tipos Spark.
 * El adapter de infraestructura realiza el cast a DataFrame.
 */
trait SourceDataPort {
  /**
   * Extrae datos de la fuente para el tipo de reporte indicado.
   * @param reportType tipo de reporte que determina la colección/tabla fuente
   * @param params     parámetros adicionales (e.g., rango de fechas para movimientos-periodo)
   * @return tupla (columnas: Map[nombre → tipo], datos: AnyRef opaco para infraestructura)
   */
  def extract(reportType: ReportType, params: Map[String, String]): (Map[String, String], AnyRef)

  /**
   * Retorna el esquema del catálogo para el tipo de reporte.
   */
  def loadSchema(reportType: ReportType): ReportSchema
}
```

```scala
// src/main/scala/com/controlstock/reporting/etl/domain/port/out/ParquetStorePort.scala
/**
 * Puerto de escritura de Parquet en MinIO.
 * La implementación concreta (SparkMinioParquetAdapter) recibe el DataFrame via AnyRef.
 */
trait ParquetStorePort {
  /**
   * Escribe los datos transformados como Parquet en MinIO.
   * @param data       DataFrame transformado (tipo AnyRef para no importar Spark en dominio)
   * @param reportType tipo de reporte (determina el sub-path en MinIO)
   * @param requestId  ID de la solicitud (parte del nombre del archivo)
   * @return path completo del archivo en MinIO
   */
  def store(data: AnyRef, reportType: ReportType, requestId: String): String
}
```

```scala
// src/main/scala/com/controlstock/reporting/etl/domain/port/out/EventBusPort.scala
/**
 * Puerto de publicación de eventos a Kafka.
 */
trait EventBusPort {
  def publishSuccess(event: ReportParquetGenerated): Unit
  def publishFailure(event: ReportEtlFailed): Unit
}
```

### Excepciones de dominio

```scala
// src/main/scala/com/controlstock/reporting/etl/domain/exception/
class UnsupportedReportTypeException(reportType: String)
  extends RuntimeException(s"Tipo de reporte no soportado: $reportType")

class ParquetStoreException(reportType: ReportType, cause: Throwable)
  extends RuntimeException(s"Error al escribir Parquet para ${reportType.value}", cause)

class EventPublishException(topic: String, cause: Throwable)
  extends RuntimeException(s"Error al publicar evento en topic $topic", cause)
```

---

## Capa de Aplicación (Scala)

### `ReportTransformerFactory`

```scala
// src/main/scala/com/controlstock/reporting/etl/application/factory/ReportTransformerFactory.scala
object ReportTransformerFactory {
  /**
   * Retorna el ReportTransformer correcto según el tipo de reporte.
   * Pattern matching exhaustivo sobre ReportType (sealed trait).
   */
  def get(reportType: ReportType): ReportTransformer = reportType match {
    case ReportType.StockActual          => StockActualReportTransformer
    case ReportType.MovimientosPeriodo   => MovimientosPeriodoReportTransformer
    case ReportType.AuditoriaOperaciones => AuditOperacionesReportTransformer
    case ReportType.ProveedoresActividad => ProveedoresActividadReportTransformer
  }

  /**
   * Variante segura para tipos no soportados (ej. tipos añadidos en el futuro
   * sin actualizar el factory).
   */
  def getOrFail(reportTypeStr: String): Either[UnsupportedReportTypeException, ReportTransformer] =
    ReportType.fromString(reportTypeStr) match {
      case Right(rt) => Right(get(rt))
      case Left(_)   => Left(new UnsupportedReportTypeException(reportTypeStr))
    }
}
```

### `ReportTransformer` trait

```scala
// src/main/scala/com/controlstock/reporting/etl/application/transformer/ReportTransformer.scala
/**
 * Transforma datos crudos (como AnyRef opaco) aplicando la lógica específica
 * del tipo de reporte: joins, filtros de fecha, aggregations.
 * La implementación concreta realiza el cast a DataFrame de Spark.
 */
trait ReportTransformer {
  /**
   * @param rawData  datos crudos del SourceDataPort (cast a DataFrame en implementación)
   * @param params   parámetros del reporte (e.g., Map("fechaInicio" → "2025-01-01"))
   * @return datos transformados (DataFrame cast a AnyRef para no importar Spark en dominio)
   */
  def transform(rawData: AnyRef, params: Map[String, String]): AnyRef
}
```

### Implementaciones de `ReportTransformer`

```scala
// src/main/scala/com/controlstock/reporting/etl/application/transformer/impl/
// StockActualReportTransformer.scala
object StockActualReportTransformer extends ReportTransformer {
  import org.apache.spark.sql.{DataFrame, functions => F}

  override def transform(rawData: AnyRef, params: Map[String, String]): AnyRef = {
    // rawData es una tupla (stock_df, productos_df) cast desde AnyRef
    val (stockDf, productosDf) = rawData.asInstanceOf[(DataFrame, DataFrame)]

    stockDf
      .join(productosDf, stockDf("producto_id") === productosDf("id"), "left")
      .select(
        stockDf("producto_id"),
        productosDf("nombre").alias("producto_nombre"),
        productosDf("sku"),
        stockDf("stock_actual"),
        stockDf("updated_at")
      )
      .withColumn("report_generated_at", F.current_timestamp())
  }
}

// MovimientosPeriodoReportTransformer.scala
object MovimientosPeriodoReportTransformer extends ReportTransformer {
  import org.apache.spark.sql.{DataFrame, functions => F}

  override def transform(rawData: AnyRef, params: Map[String, String]): AnyRef = {
    val df = rawData.asInstanceOf[DataFrame]
    val fechaInicio = params.getOrElse("fechaInicio", "1970-01-01")
    val fechaFin    = params.getOrElse("fechaFin",    "9999-12-31")

    df.filter(
      F.col("fecha").between(fechaInicio, fechaFin)
    ).select(
      F.col("id").alias("movimiento_id"),
      F.col("producto_id"),
      F.col("tipo"),         // ENTRADA, SALIDA, AJUSTE
      F.col("cantidad"),
      F.col("saldo_resultante"),
      F.col("referencia_documento"),
      F.col("fecha"),
      F.col("created_at")
    ).orderBy(F.col("fecha").desc)
  }
}

// AuditOperacionesReportTransformer.scala
// Fuente: PostgreSQL via JDBC (no MongoDB)
object AuditOperacionesReportTransformer extends ReportTransformer {
  import org.apache.spark.sql.{DataFrame, functions => F}

  override def transform(rawData: AnyRef, params: Map[String, String]): AnyRef = {
    val df = rawData.asInstanceOf[DataFrame]  // audit_log DataFrame via JDBC

    df.select(
      F.col("id").alias("audit_id"),
      F.col("entity_type"),
      F.col("entity_id"),
      F.col("action"),        // CREATE, UPDATE, DELETE, LOGIN, etc.
      F.col("usuario_id"),
      F.col("details"),       // JSONB como String en JDBC
      F.col("created_at")
    ).orderBy(F.col("created_at").desc)
  }
}

// ProveedoresActividadReportTransformer.scala
object ProveedoresActividadReportTransformer extends ReportTransformer {
  import org.apache.spark.sql.{DataFrame, functions => F}

  override def transform(rawData: AnyRef, params: Map[String, String]): AnyRef = {
    val (proveedoresDf, movimientosDf) = rawData.asInstanceOf[(DataFrame, DataFrame)]

    val entradasPorProveedor = movimientosDf
      .filter(F.col("tipo") === "ENTRADA")
      .filter(F.col("proveedor_id").isNotNull)
      .groupBy(F.col("proveedor_id"))
      .agg(
        F.count("id").alias("total_entradas"),
        F.sum("cantidad").alias("volumen_total"),
        F.max("fecha").alias("ultima_entrada")
      )

    proveedoresDf
      .join(entradasPorProveedor,
        proveedoresDf("id") === entradasPorProveedor("proveedor_id"), "left")
      .select(
        proveedoresDf("id").alias("proveedor_id"),
        proveedoresDf("nombre").alias("proveedor_nombre"),
        proveedoresDf("tipo_conexion"),
        entradasPorProveedor("total_entradas"),
        entradasPorProveedor("volumen_total"),
        entradasPorProveedor("ultima_entrada")
      )
  }
}
```

### `ExtractReportUseCase`

```scala
// src/main/scala/com/controlstock/reporting/etl/application/usecase/ExtractReportUseCase.scala
class ExtractReportUseCase(
  mongoSource:  SourceDataPort,
  jdbcSource:   SourceDataPort,
  parquetStore: ParquetStorePort,
  eventBus:     EventBusPort
) {
  private val logger = org.slf4j.LoggerFactory.getLogger(getClass)

  /**
   * Ejecuta el pipeline ETL completo para un tipo de reporte y una solicitud.
   *
   * 1. Selecciona el SourceDataPort correcto según el tipo de reporte
   * 2. Extrae datos crudos
   * 3. Valida esquema contra el catálogo
   * 4. Aplica el transformer específico
   * 5. Almacena como Parquet en MinIO
   * 6. Publica evento de éxito o fallo
   */
  def execute(
    reportType: ReportType,
    requestId: String,
    params: Map[String, String]
  ): Unit = {
    logger.info(s"Iniciando ETL para requestId=$requestId, reportType=${reportType.value}")

    val result: Either[Throwable, ReportParquetGenerated] =
      try {
        // 1. Seleccionar fuente correcta
        val sourcePort = selectSource(reportType)

        // 2. Cargar esquema del catálogo
        val schema = sourcePort.loadSchema(reportType)

        // 3. Extraer datos crudos
        val (presentColumns, rawData) = sourcePort.extract(reportType, params)

        // 4. Validar esquema
        schema.validate(presentColumns) match {
          case Left(validationError) =>
            throw new RuntimeException(validationError.toMessage)
          case Right(_) =>
            logger.info(s"Esquema validado para ${reportType.value}")
        }

        // 5. Transformar
        val transformer = ReportTransformerFactory.get(reportType)
        val transformedData = transformer.transform(rawData, params)

        // 6. Almacenar Parquet
        val parquetPath = parquetStore.store(transformedData, reportType, requestId)
        logger.info(s"Parquet almacenado en: $parquetPath")

        // 7. Calcular rowCount (cast a DataFrame en infraestructura; aquí opaco)
        val rowCount = transformedData match {
          case df: org.apache.spark.sql.DataFrame => df.count()
          case (df1: org.apache.spark.sql.DataFrame, _) => df1.count()
          case _ => -1L
        }

        Right(ReportParquetGenerated(
          requestId = requestId,
          reportType = reportType,
          parquetPath = parquetPath,
          rowCount = rowCount,
          generatedAt = java.time.Instant.now()
        ))

      } catch {
        case ex: Throwable =>
          logger.error(s"ETL fallido para requestId=$requestId: ${ex.getMessage}", ex)
          Left(ex)
      }

    // 8. Publicar evento
    result match {
      case Right(event) =>
        eventBus.publishSuccess(event)
        logger.info(s"ReporteParquetGenerado publicado para requestId=$requestId")

      case Left(cause) =>
        eventBus.publishFailure(ReportEtlFailed(
          requestId = requestId,
          reportType = reportType,
          reason = cause.getMessage,
          failedAt = java.time.Instant.now()
        ))
        logger.warn(s"ReporteETLFallido publicado para requestId=$requestId")
    }
  }

  private def selectSource(reportType: ReportType): SourceDataPort = reportType match {
    case ReportType.AuditoriaOperaciones => jdbcSource
    case _                               => mongoSource
  }
}
```

---

## Capa de Infraestructura (Spark)

### Configuración SparkSession

```scala
// src/main/scala/com/controlstock/reporting/etl/infrastructure/spark/SparkSessionFactory.scala
object SparkSessionFactory {

  def create(config: EtlConfig): SparkSession = {
    SparkSession.builder()
      .appName("report-etl-service")
      .master(config.sparkMaster)   // "local[*]" en tests; "k8s://..." en producción
      // MongoDB Connector
      .config("spark.mongodb.read.connection.uri", config.mongoUri)
      .config("spark.mongodb.read.database", "controlstock_readmodel")
      // MinIO / S3
      .config("spark.hadoop.fs.s3a.endpoint",            config.minioEndpoint)
      .config("spark.hadoop.fs.s3a.access.key",          config.minioAccessKey)
      .config("spark.hadoop.fs.s3a.secret.key",          config.minioSecretKey)
      .config("spark.hadoop.fs.s3a.path.style.access",   "true")
      .config("spark.hadoop.fs.s3a.impl",
        "org.apache.hadoop.fs.s3a.S3AFileSystem")
      .config("spark.hadoop.fs.s3a.aws.credentials.provider",
        "org.apache.hadoop.fs.s3a.SimpleAWSCredentialsProvider")
      // OTEL para trazas del job
      .config("spark.jars",             config.otelAgentJar)
      .config("spark.driver.extraJavaOptions",
        s"-javaagent:${config.otelAgentJar} " +
        s"-Dotel.service.name=report-etl-service " +
        s"-Dotel.exporter.otlp.endpoint=${config.otelEndpoint}")
      .getOrCreate()
  }
}

// EtlConfig.scala — cargada desde Vault vía env vars al inicio del job
case class EtlConfig(
  sparkMaster: String,
  mongoUri: String,         // desde Vault: secret/report-etl-service/mongodb/uri
  jdbcUrl: String,          // desde Vault: secret/report-etl-service/postgresql/url
  jdbcUser: String,
  jdbcPassword: String,
  minioEndpoint: String,    // desde Vault: secret/report-etl-service/minio/endpoint
  minioAccessKey: String,
  minioSecretKey: String,
  kafkaBootstrapServers: String,
  otelAgentJar: String,
  otelEndpoint: String
)
```

### `SparkMongoSourceAdapter` (implementa `SourceDataPort` para MongoDB)

```scala
// src/main/scala/com/controlstock/reporting/etl/infrastructure/adapter/SparkMongoSourceAdapter.scala
class SparkMongoSourceAdapter(
  spark: SparkSession,
  jdbcUrl: String,      // para leer report_schema_catalog vía JDBC
  jdbcUser: String,
  jdbcPassword: String
) extends SourceDataPort {

  import com.mongodb.spark.sql._
  import org.apache.spark.sql.{DataFrame, functions => F}

  override def extract(
    reportType: ReportType,
    params: Map[String, String]
  ): (Map[String, String], AnyRef) = {

    val rawData: AnyRef = reportType match {
      case ReportType.StockActual =>
        val stockDf  = spark.read.format("mongodb")
          .option("collection", "stock").load()
        val prodDf   = spark.read.format("mongodb")
          .option("collection", "productos").load()
        (stockDf, prodDf)  // tupla para join en transformer

      case ReportType.MovimientosPeriodo =>
        spark.read.format("mongodb")
          .option("collection", "movimientos").load()

      case ReportType.AuditoriaOperaciones =>
        throw new UnsupportedOperationException(
          "auditoria-operaciones usa SparkJdbcSourceAdapter, no MongoDB")

      case ReportType.ProveedoresActividad =>
        val provDf  = spark.read.format("mongodb")
          .option("collection", "proveedores").load()
        val movDf   = spark.read.format("mongodb")
          .option("collection", "movimientos").load()
        (provDf, movDf)
    }

    // Extraer columnas presentes del DataFrame para validación de esquema
    val presentColumns: Map[String, String] = rawData match {
      case df: DataFrame =>
        df.schema.fields.map(f => f.name -> f.dataType.typeName).toMap
      case (df1: DataFrame, _) =>
        df1.schema.fields.map(f => f.name -> f.dataType.typeName).toMap
    }

    (presentColumns, rawData)
  }

  override def loadSchema(reportType: ReportType): ReportSchema = {
    // Lee report_schema_catalog de PostgreSQL controlstock_reporting via JDBC
    val catalogDf = spark.read
      .format("jdbc")
      .option("url",      jdbcUrl)
      .option("dbtable",  "report_schema_catalog")
      .option("user",     jdbcUser)
      .option("password", jdbcPassword)
      .load()
      .filter(F.col("report_type") === reportType.value)

    val row = catalogDf.collect().headOption
      .getOrElse(throw new RuntimeException(
        s"No se encontró esquema en catálogo para: ${reportType.value}"))

    // Deserializar column_specs (JSONB almacenado como String en JDBC)
    val columnSpecsJson = row.getAs[String]("column_specs")
    val columnSpecs = parseColumnSpecs(columnSpecsJson)

    ReportSchema(reportType, columnSpecs)
  }

  private def parseColumnSpecs(json: String): Seq[ColumnSpec] = {
    // Parseo simple con circe o spray-json
    import io.circe.parser._
    import io.circe.generic.auto._
    decode[Seq[ColumnSpec]](json)
      .getOrElse(throw new RuntimeException(s"No se pudo parsear column_specs: $json"))
  }
}
```

### `SparkJdbcSourceAdapter` (implementa `SourceDataPort` para PostgreSQL)

```scala
// src/main/scala/com/controlstock/reporting/etl/infrastructure/adapter/SparkJdbcSourceAdapter.scala
class SparkJdbcSourceAdapter(
  spark: SparkSession,
  auditJdbcUrl: String,
  reportingJdbcUrl: String,
  jdbcUser: String,
  jdbcPassword: String
) extends SourceDataPort {

  import org.apache.spark.sql.{DataFrame, functions => F}

  override def extract(
    reportType: ReportType,
    params: Map[String, String]
  ): (Map[String, String], AnyRef) = {

    reportType match {
      case ReportType.AuditoriaOperaciones =>
        val auditDf: DataFrame = spark.read
          .format("jdbc")
          .option("url",      auditJdbcUrl)
          .option("dbtable",  "audit_log")
          .option("user",     jdbcUser)
          .option("password", jdbcPassword)
          .option("fetchsize", "10000")   // batch size para JDBC eficiente
          .load()

        val presentColumns = auditDf.schema.fields
          .map(f => f.name -> f.dataType.typeName).toMap

        (presentColumns, auditDf)

      case other =>
        throw new UnsupportedOperationException(
          s"SparkJdbcSourceAdapter no soporta: ${other.value}")
    }
  }

  override def loadSchema(reportType: ReportType): ReportSchema = {
    val catalogDf = spark.read
      .format("jdbc")
      .option("url",      reportingJdbcUrl)
      .option("dbtable",  "report_schema_catalog")
      .option("user",     jdbcUser)
      .option("password", jdbcPassword)
      .load()
      .filter(F.col("report_type") === reportType.value)

    val row = catalogDf.collect().headOption
      .getOrElse(throw new RuntimeException(
        s"No se encontró esquema en catálogo para: ${reportType.value}"))

    val columnSpecs = parseColumnSpecs(row.getAs[String]("column_specs"))
    ReportSchema(reportType, columnSpecs)
  }

  private def parseColumnSpecs(json: String): Seq[ColumnSpec] = {
    import io.circe.parser._
    import io.circe.generic.auto._
    decode[Seq[ColumnSpec]](json)
      .getOrElse(throw new RuntimeException(s"No se pudo parsear column_specs: $json"))
  }
}
```

### `SparkMinioParquetAdapter` (implementa `ParquetStorePort`)

```scala
// src/main/scala/com/controlstock/reporting/etl/infrastructure/adapter/SparkMinioParquetAdapter.scala
class SparkMinioParquetAdapter(spark: SparkSession, bucketName: String) extends ParquetStorePort {

  import org.apache.spark.sql.DataFrame

  /**
   * Escribe el DataFrame como Parquet en MinIO via S3A connector.
   * Path: s3a://{bucket}/parquet/{report_type}/{year}/{month}/{request_id}.parquet
   */
  override def store(data: AnyRef, reportType: ReportType, requestId: String): String = {
    val df = data.asInstanceOf[DataFrame]

    val now = java.time.LocalDate.now()
    val year  = now.getYear
    val month = f"${now.getMonthValue}%02d"

    val parquetPath = s"s3a://$bucketName/parquet/${reportType.value}/$year/$month/$requestId.parquet"

    df.write
      .mode("overwrite")
      .parquet(parquetPath)

    // Retornar el path relativo (sin s3a://bucket) para almacenar en report_files
    s"parquet/${reportType.value}/$year/$month/$requestId.parquet"
  }
}
```

### `KafkaEventPublisher` (implementa `EventBusPort`)

```scala
// src/main/scala/com/controlstock/reporting/etl/infrastructure/adapter/KafkaEventPublisher.scala
class KafkaEventPublisher(bootstrapServers: String) extends EventBusPort {

  import org.apache.kafka.clients.producer.{KafkaProducer, ProducerConfig, ProducerRecord}
  import java.util.Properties

  private val props = {
    val p = new Properties()
    p.put(ProducerConfig.BOOTSTRAP_SERVERS_CONFIG,       bootstrapServers)
    p.put(ProducerConfig.KEY_SERIALIZER_CLASS_CONFIG,
      "org.apache.kafka.common.serialization.StringSerializer")
    p.put(ProducerConfig.VALUE_SERIALIZER_CLASS_CONFIG,
      "org.apache.kafka.common.serialization.StringSerializer")
    p.put(ProducerConfig.ACKS_CONFIG, "all")
    p.put(ProducerConfig.RETRIES_CONFIG, "3")
    p
  }

  private val producer = new KafkaProducer[String, String](props)

  override def publishSuccess(event: ReportParquetGenerated): Unit = {
    import io.circe.syntax._
    import io.circe.generic.auto._
    val json = event.asJson.noSpaces
    val record = new ProducerRecord[String, String](
      "controlstock.reporting.parquet-generado",
      event.requestId,
      json
    )
    producer.send(record).get()  // sync para garantizar entrega antes de terminar el job
  }

  override def publishFailure(event: ReportEtlFailed): Unit = {
    import io.circe.syntax._
    import io.circe.generic.auto._
    val json = event.asJson.noSpaces
    val record = new ProducerRecord[String, String](
      "controlstock.reporting.etl-fallido",
      event.requestId,
      json
    )
    producer.send(record).get()
  }

  def close(): Unit = producer.close()
}
```

### EntryPoint principal

```scala
// src/main/scala/com/controlstock/reporting/etl/EntryPoint.scala
object EntryPoint {

  private val logger = org.slf4j.LoggerFactory.getLogger(getClass)

  def main(args: Array[String]): Unit = {
    logger.info("Report ETL Service iniciando...")

    val config = loadConfig()
    val spark  = SparkSessionFactory.create(config)

    val mongoSource  = new SparkMongoSourceAdapter(
      spark, config.jdbcUrl, config.jdbcUser, config.jdbcPassword)
    val jdbcSource   = new SparkJdbcSourceAdapter(
      spark,
      auditJdbcUrl = config.jdbcUrl.replace("controlstock_reporting", "controlstock_audit"),
      reportingJdbcUrl = config.jdbcUrl,
      config.jdbcUser, config.jdbcPassword)
    val parquetStore = new SparkMinioParquetAdapter(spark, "controlstock-reports")
    val eventBus     = new KafkaEventPublisher(config.kafkaBootstrapServers)

    val useCase = new ExtractReportUseCase(mongoSource, jdbcSource, parquetStore, eventBus)

    try {
      // Modo 1: on-demand vía argumento de línea de comandos (desde Kafka consumer trigger)
      if (args.length >= 2) {
        val reportTypeStr = args(0)
        val requestId     = args(1)
        val params        = if (args.length > 2) parseParams(args.drop(2)) else Map.empty[String, String]

        ReportType.fromString(reportTypeStr) match {
          case Right(reportType) =>
            useCase.execute(reportType, requestId, params)
          case Left(err) =>
            logger.error(err)
            eventBus.publishFailure(ReportEtlFailed(
              requestId     = requestId,
              reportType    = ReportType.StockActual,   // fallback para el evento
              reason        = err,
              failedAt      = java.time.Instant.now()
            ))
        }
      } else {
        // Modo 2: CronJob schedule — procesar todos los tipos pendientes de solicitudes Kafka
        logger.info("Modo CronJob: procesando solicitudes pendientes en Kafka")
        processPendingRequests(useCase, config, eventBus)
      }
    } finally {
      eventBus.close()
      spark.stop()
      logger.info("Report ETL Service finalizado.")
    }
  }

  private def processPendingRequests(
    useCase: ExtractReportUseCase,
    config: EtlConfig,
    eventBus: KafkaEventPublisher
  ): Unit = {
    // Consumir todos los mensajes disponibles en controlstock.reporting.requests
    // con un poll de duración acotada (max 5 minutos de lectura)
    import org.apache.kafka.clients.consumer.{ConsumerConfig, KafkaConsumer}
    import io.circe.parser._
    import java.time.Duration

    val consumerProps = new java.util.Properties()
    consumerProps.put(ConsumerConfig.BOOTSTRAP_SERVERS_CONFIG, config.kafkaBootstrapServers)
    consumerProps.put(ConsumerConfig.GROUP_ID_CONFIG,          "report-etl-service-batch")
    consumerProps.put(ConsumerConfig.AUTO_OFFSET_RESET_CONFIG, "earliest")
    consumerProps.put(ConsumerConfig.MAX_POLL_RECORDS_CONFIG,  "50")
    consumerProps.put(ConsumerConfig.KEY_DESERIALIZER_CLASS_CONFIG,
      "org.apache.kafka.common.serialization.StringDeserializer")
    consumerProps.put(ConsumerConfig.VALUE_DESERIALIZER_CLASS_CONFIG,
      "org.apache.kafka.common.serialization.StringDeserializer")

    val consumer = new KafkaConsumer[String, String](consumerProps)
    consumer.subscribe(java.util.Collections.singletonList("controlstock.reporting.requests"))

    val deadline = java.time.Instant.now().plusSeconds(300)  // 5 min max
    var processed = 0

    while (java.time.Instant.now().isBefore(deadline)) {
      val records = consumer.poll(Duration.ofSeconds(10))
      if (records.isEmpty) {
        logger.info(s"No hay más solicitudes pendientes. Total procesadas: $processed")
        consumer.close()
        return
      }

      records.forEach { record =>
        parse(record.value()).flatMap(_.as[SolicitudReporteGeneradaDto]) match {
          case Right(solicitud) =>
            ReportType.fromString(solicitud.reportType) match {
              case Right(rt) =>
                useCase.execute(rt, solicitud.requestId, solicitud.params)
                processed += 1
              case Left(err) =>
                logger.error(s"Tipo desconocido en solicitud: $err")
            }
          case Left(err) =>
            logger.error(s"No se pudo deserializar solicitud: $err")
        }
      }
      consumer.commitSync()
    }

    logger.warn("Deadline de 5 minutos alcanzado en processPendingRequests")
    consumer.close()
  }

  private def loadConfig(): EtlConfig = {
    def env(key: String): String =
      sys.env.getOrElse(key, throw new RuntimeException(s"Variable de entorno faltante: $key"))

    EtlConfig(
      sparkMaster          = sys.env.getOrElse("SPARK_MASTER", "local[*]"),
      mongoUri             = env("MONGO_URI"),
      jdbcUrl              = env("REPORTING_JDBC_URL"),
      jdbcUser             = env("REPORTING_JDBC_USER"),
      jdbcPassword         = env("REPORTING_JDBC_PASSWORD"),
      minioEndpoint        = env("MINIO_ENDPOINT"),
      minioAccessKey       = env("MINIO_ACCESS_KEY"),
      minioSecretKey       = env("MINIO_SECRET_KEY"),
      kafkaBootstrapServers = env("KAFKA_BOOTSTRAP_SERVERS"),
      otelAgentJar         = sys.env.getOrElse("OTEL_AGENT_JAR", "/opt/opentelemetry-javaagent.jar"),
      otelEndpoint         = sys.env.getOrElse("OTEL_EXPORTER_OTLP_ENDPOINT",
        "http://otel-collector.monitoring.svc.cluster.local:4318")
    )
  }

  private def parseParams(args: Array[String]): Map[String, String] =
    args.flatMap(a => a.split("=", 2) match {
      case Array(k, v) => Some(k -> v)
      case _           => None
    }).toMap
}

// DTO para deserializar mensajes Kafka de solicitud
case class SolicitudReporteGeneradaDto(
  requestId: String,
  reportType: String,
  params: Map[String, String]
)
```

### `build.sbt` — dependencias clave

```scala
// build.sbt
name := "report-etl-service"
version := "0.1.0-SNAPSHOT"
scalaVersion := "2.13.13"

val sparkVersion = "3.5.0"

libraryDependencies ++= Seq(
  // Spark core
  "org.apache.spark" %% "spark-core" % sparkVersion % "provided",
  "org.apache.spark" %% "spark-sql"  % sparkVersion % "provided",

  // MongoDB Connector for Spark
  "org.mongodb.spark" %% "mongo-spark-connector" % "10.3.0",

  // S3A para MinIO
  "org.apache.hadoop" % "hadoop-aws" % "3.3.4",
  "com.amazonaws"     % "aws-java-sdk-bundle" % "1.12.576",

  // Kafka producer/consumer
  "org.apache.kafka" % "kafka-clients" % "3.6.1",

  // Circe para JSON
  "io.circe" %% "circe-core"           % "0.14.6",
  "io.circe" %% "circe-generic"        % "0.14.6",
  "io.circe" %% "circe-parser"         % "0.14.6",

  // Tests
  "org.scalatest"    %% "scalatest"                % "3.2.17"   % Test,
  "org.apache.spark" %% "spark-sql"               % sparkVersion % Test,
  "com.dimafeng"     %% "testcontainers-scala-mongodb"    % "0.41.3" % Test,
  "com.dimafeng"     %% "testcontainers-scala-postgresql" % "0.41.3" % Test,
  "io.github.embeddedkafka" %% "embedded-kafka"   % "3.6.1"    % Test
)

// Fat JAR para spark-submit
assembly / assemblyMergeStrategy := {
  case PathList("META-INF", xs @ _*) => MergeStrategy.discard
  case "reference.conf"              => MergeStrategy.concat
  case x                             => MergeStrategy.first
}

assembly / mainClass := Some("com.controlstock.reporting.etl.EntryPoint")
```

---

## CronJob Deployment

### Manifiesto Kubernetes CronJob

```yaml
# k8s/report-etl-service/cronjob.yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: report-etl-service
  namespace: apps
  labels:
    app: report-etl-service
    version: "0.1.0"
    component: batch
spec:
  schedule: "0 2 * * *"    # Diariamente a las 2 AM UTC
  concurrencyPolicy: Forbid  # No ejecutar si hay un job corriendo (evitar solapamiento)
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 5
  jobTemplate:
    spec:
      backoffLimit: 1        # Máximo 1 reintento si el job falla
      activeDeadlineSeconds: 1800  # Timeout máximo: 30 minutos
      template:
        metadata:
          labels:
            app: report-etl-service
            component: batch
        spec:
          restartPolicy: Never   # OBLIGATORIO para CronJob batch
          serviceAccountName: report-etl-sa
          containers:
          - name: report-etl
            image: registry.<VPS_IP>/controlstock/report-etl-service:latest
            command: ["spark-submit"]
            args:
            - "--master"
            - "local[*]"
            - "--class"
            - "com.controlstock.reporting.etl.EntryPoint"
            - "--conf"
            - "spark.driver.extraJavaOptions=$(JAVA_TOOL_OPTIONS)"
            - "/app/report-etl-service-assembly.jar"
            env:
            # Credenciales desde Vault via vault-agent sidecar injection
            - name: MONGO_URI
              valueFrom:
                secretKeyRef:
                  name: report-etl-secrets
                  key: mongo-uri
            - name: REPORTING_JDBC_URL
              valueFrom:
                secretKeyRef:
                  name: report-etl-secrets
                  key: reporting-jdbc-url
            - name: REPORTING_JDBC_USER
              valueFrom:
                secretKeyRef:
                  name: report-etl-secrets
                  key: reporting-jdbc-user
            - name: REPORTING_JDBC_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: report-etl-secrets
                  key: reporting-jdbc-password
            - name: MINIO_ENDPOINT
              valueFrom:
                secretKeyRef:
                  name: report-etl-secrets
                  key: minio-endpoint
            - name: MINIO_ACCESS_KEY
              valueFrom:
                secretKeyRef:
                  name: report-etl-secrets
                  key: minio-access-key
            - name: MINIO_SECRET_KEY
              valueFrom:
                secretKeyRef:
                  name: report-etl-secrets
                  key: minio-secret-key
            - name: KAFKA_BOOTSTRAP_SERVERS
              value: "kafka.kafka.svc.cluster.local:9092"
            # OTEL Agent para trazas del job Spark
            - name: JAVA_TOOL_OPTIONS
              value: >-
                -javaagent:/opt/opentelemetry-javaagent.jar
                -Dotel.service.name=report-etl-service
                -Dotel.resource.attributes=deployment.environment=dev
                -Dotel.exporter.otlp.endpoint=http://otel-collector.monitoring.svc.cluster.local:4318
                -Dotel.exporter.otlp.protocol=http/protobuf
            - name: OTEL_AGENT_JAR
              value: "/opt/opentelemetry-javaagent.jar"
            resources:
              requests:
                memory: "2Gi"
                cpu: "500m"
              limits:
                memory: "4Gi"
                cpu: "2000m"
            volumeMounts:
            - name: vault-secrets
              mountPath: /vault/secrets
              readOnly: true
          volumes:
          - name: vault-secrets
            secret:
              secretName: report-etl-secrets
```

### Verificación de CronJob en K3s

```bash
# Ver estado del CronJob
kubectl get cronjob report-etl-service -n apps
# SCHEDULE      SUSPEND   ACTIVE   LAST SCHEDULE   AGE
# 0 2 * * *     False     0        <none>          5m

# Lanzar ejecución manual (para verificación post-deploy)
kubectl create job --from=cronjob/report-etl-service \
  report-etl-manual-$(date +%Y%m%d%H%M%S) \
  -n apps

# Seguir logs del job
JOB_POD=$(kubectl get pods -n apps --selector=job-name=report-etl-manual-* \
  --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1].metadata.name}')
kubectl logs -n apps $JOB_POD -f

# Ver historial de jobs
kubectl get jobs -n apps --selector=app=report-etl-service
# NAME                           COMPLETIONS   DURATION   AGE
# report-etl-service-28XXXX      1/1           8m         1d
# report-etl-manual-20250101     1/1           5m         5m
```

### Pipeline Jenkins — diferencias con microservicios REST

```
Jenkins Pipeline — report-etl-service:

Stage 1: Checkout           (git clone)
Stage 2: sbt compile        (compilar Scala)
Stage 3: sbt test           (ejecutar tests)
Stage 4: sbt assembly       (generar fat JAR)
Stage 5: Docker build       (imagen con FAT JAR + spark-submit)
Stage 6: Docker push        (push a registry)
Stage 7: bumpImageTag       (actualizar tag en repo ArgoCD)
         ← PIPELINE TERMINA AQUÍ

NO Stage 8: smoke test      (imposible — CronJob no tiene endpoint)
NO Stage 9: health check    (CronJob sin actuator)

ArgoCD detecta el cambio de tag y sincroniza el CronJob spec.
La verificación manual se hace con kubectl create job --from=cronjob/...
```

---

## Especificación TDD — sbt test

### Framework de testing: ScalaTest + Testcontainers-Scala + EmbeddedKafka

Todos los tests usan `sbt test` (NO `mvn test`). SparkSession en tests usa `master("local[1]")` para ejecución en proceso. Las aserciones usan el estilo `AnyFlatSpec` con `should matchers` de ScalaTest.

### Tests de Dominio

#### `ReportSchemaTest`

```scala
// src/test/scala/com/controlstock/reporting/etl/domain/ReportSchemaTest.scala
class ReportSchemaTest extends AnyFlatSpec with Matchers {

  "ReportSchema.validate" should "retornar Right(()) cuando todas las columnas están presentes" in {
    val schema = ReportSchema(
      ReportType.StockActual,
      Seq(
        ColumnSpec("producto_id",   "StringType"),
        ColumnSpec("stock_actual",  "LongType"),
        ColumnSpec("updated_at",    "TimestampType")
      )
    )
    val presentColumns = Map(
      "producto_id"  -> "StringType",
      "stock_actual" -> "LongType",
      "updated_at"   -> "TimestampType",
      "extra_col"    -> "StringType"   // columnas extra no causan fallo
    )

    schema.validate(presentColumns) shouldBe Right(())
  }

  it should "retornar Left con columnas faltantes" in {
    val schema = ReportSchema(
      ReportType.StockActual,
      Seq(
        ColumnSpec("producto_id",  "StringType"),
        ColumnSpec("stock_actual", "LongType"),
        ColumnSpec("sku",          "StringType")  // ← esta falta
      )
    )
    val presentColumns = Map(
      "producto_id"  -> "StringType",
      "stock_actual" -> "LongType"
      // "sku" ausente
    )

    val result = schema.validate(presentColumns)
    result shouldBe a[Left[_, _]]
    result.left.get.missingColumns should contain("sku")
    result.left.get.toMessage should include("sku")
  }

  it should "retornar Left con tipos incorrectos" in {
    val schema = ReportSchema(
      ReportType.MovimientosPeriodo,
      Seq(ColumnSpec("cantidad", "LongType"))
    )
    val presentColumns = Map("cantidad" -> "DoubleType")  // tipo incorrecto

    val result = schema.validate(presentColumns)
    result shouldBe a[Left[_, _]]
    result.left.get.wrongTypeColumns should not be empty
    result.left.get.toMessage should include("cantidad")
  }
}
```

#### `ReportTypeTest`

```scala
class ReportTypeTest extends AnyFlatSpec with Matchers {

  "ReportType.fromString" should "parsear todos los tipos válidos" in {
    ReportType.fromString("stock-actual")           shouldBe Right(ReportType.StockActual)
    ReportType.fromString("movimientos-periodo")    shouldBe Right(ReportType.MovimientosPeriodo)
    ReportType.fromString("auditoria-operaciones")  shouldBe Right(ReportType.AuditoriaOperaciones)
    ReportType.fromString("proveedores-actividad")  shouldBe Right(ReportType.ProveedoresActividad)
  }

  it should "retornar Left para tipo desconocido" in {
    ReportType.fromString("tipo-inexistente") shouldBe a[Left[_, _]]
  }
}
```

### Tests de Aplicación — ReportTransformerFactory

```scala
// src/test/scala/com/controlstock/reporting/etl/application/ReportTransformerFactoryTest.scala
class ReportTransformerFactoryTest extends AnyFlatSpec with Matchers {

  "ReportTransformerFactory.get" should "retornar StockActualReportTransformer para stock-actual" in {
    ReportTransformerFactory.get(ReportType.StockActual) shouldBe StockActualReportTransformer
  }

  it should "retornar MovimientosPeriodoReportTransformer para movimientos-periodo" in {
    ReportTransformerFactory.get(ReportType.MovimientosPeriodo) shouldBe
      MovimientosPeriodoReportTransformer
  }

  it should "retornar AuditOperacionesReportTransformer para auditoria-operaciones" in {
    ReportTransformerFactory.get(ReportType.AuditoriaOperaciones) shouldBe
      AuditOperacionesReportTransformer
  }

  it should "retornar ProveedoresActividadReportTransformer para proveedores-actividad" in {
    ReportTransformerFactory.get(ReportType.ProveedoresActividad) shouldBe
      ProveedoresActividadReportTransformer
  }

  "ReportTransformerFactory.getOrFail" should "retornar Left para tipo desconocido" in {
    val result = ReportTransformerFactory.getOrFail("tipo-invalido")
    result shouldBe a[Left[_, _]]
    result.left.get shouldBe an[UnsupportedReportTypeException]
  }
}
```

### Tests de Aplicación — Transformers con SparkSession local

```scala
// src/test/scala/com/controlstock/reporting/etl/application/StockActualTransformerTest.scala
class StockActualTransformerTest extends AnyFlatSpec with Matchers with BeforeAndAfterAll {

  private var spark: SparkSession = _

  override def beforeAll(): Unit = {
    spark = SparkSession.builder()
      .appName("StockActualTransformerTest")
      .master("local[1]")
      .getOrCreate()
  }

  override def afterAll(): Unit = spark.stop()

  "StockActualReportTransformer" should "hacer join de stock con productos y seleccionar columnas" in {
    import spark.implicits._

    val stockDf = Seq(
      ("prod-001", 100L, java.sql.Timestamp.from(java.time.Instant.now())),
      ("prod-002",  50L, java.sql.Timestamp.from(java.time.Instant.now()))
    ).toDF("producto_id", "stock_actual", "updated_at")

    val productosDf = Seq(
      ("prod-001", "Arroz 1kg",   "ARR-001"),
      ("prod-002", "Azúcar 1kg",  "AZU-001")
    ).toDF("id", "nombre", "sku")

    val rawData = (stockDf, productosDf)
    val result  = StockActualReportTransformer.transform(rawData, Map.empty)
      .asInstanceOf[org.apache.spark.sql.DataFrame]

    result.count() shouldBe 2
    result.columns should contain allOf ("producto_id", "producto_nombre", "sku", "stock_actual")
    result.filter($"producto_id" === "prod-001")
      .select("producto_nombre").collect().head.getString(0) shouldBe "Arroz 1kg"
  }
}
```

```scala
class MovimientosPeriodoTransformerTest extends AnyFlatSpec with Matchers with BeforeAndAfterAll {

  private var spark: SparkSession = _

  override def beforeAll(): Unit =
    spark = SparkSession.builder().appName("MovimientosTest").master("local[1]").getOrCreate()
  override def afterAll(): Unit = spark.stop()

  "MovimientosPeriodoReportTransformer" should "filtrar por rango de fechas" in {
    import spark.implicits._

    val movDf = Seq(
      ("mov-1", "prod-001", "ENTRADA", 10L, "2025-01-10"),
      ("mov-2", "prod-001", "SALIDA",   5L, "2025-02-15"),
      ("mov-3", "prod-002", "ENTRADA", 20L, "2024-12-01")  // fuera del rango
    ).toDF("id", "producto_id", "tipo", "cantidad", "fecha")

    val params = Map("fechaInicio" -> "2025-01-01", "fechaFin" -> "2025-12-31")
    val result = MovimientosPeriodoReportTransformer.transform(movDf, params)
      .asInstanceOf[org.apache.spark.sql.DataFrame]

    result.count() shouldBe 2   // mov-3 excluido (fecha 2024)
    result.columns should contain allOf ("movimiento_id", "tipo", "cantidad", "fecha")
  }
}
```

### Tests de Infraestructura — `SparkJdbcSourceAdapter` con Testcontainers PostgreSQL

```scala
// src/test/scala/com/controlstock/reporting/etl/infrastructure/SparkJdbcSourceAdapterTest.scala
class SparkJdbcSourceAdapterTest extends AnyFlatSpec with Matchers
    with BeforeAndAfterAll with ForAllTestContainer {

  override val container: PostgreSQLContainer = PostgreSQLContainer("postgres:16")

  private var spark: SparkSession = _

  override def beforeAll(): Unit = {
    super.beforeAll()
    spark = SparkSession.builder().appName("JdbcTest").master("local[1]").getOrCreate()

    // Seed audit_log con datos de prueba
    val conn = java.sql.DriverManager.getConnection(
      container.jdbcUrl, container.username, container.password)
    val stmt = conn.createStatement()
    stmt.execute("""
      CREATE TABLE IF NOT EXISTS audit_log (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        entity_type VARCHAR(100),
        entity_id UUID,
        action VARCHAR(50),
        usuario_id UUID,
        details TEXT,
        created_at TIMESTAMPTZ DEFAULT NOW()
      )
    """)
    stmt.execute("""
      INSERT INTO audit_log (entity_type, entity_id, action, usuario_id, details)
      VALUES
        ('StockLevel', gen_random_uuid(), 'UPDATE', gen_random_uuid(), '{"campo":"stock_actual"}'),
        ('AdjustmentRequest', gen_random_uuid(), 'CREATE', gen_random_uuid(), '{}')
    """)
    conn.close()
  }

  override def afterAll(): Unit = {
    spark.stop()
    super.afterAll()
  }

  "SparkJdbcSourceAdapter" should "leer audit_log y retornar columnas correctas" in {
    val adapter = new SparkJdbcSourceAdapter(
      spark,
      auditJdbcUrl    = container.jdbcUrl,
      reportingJdbcUrl = container.jdbcUrl,
      jdbcUser         = container.username,
      jdbcPassword     = container.password
    )

    val (presentColumns, rawData) = adapter.extract(
      ReportType.AuditoriaOperaciones, Map.empty)

    presentColumns should contain key "entity_type"
    presentColumns should contain key "action"
    presentColumns should contain key "usuario_id"

    val df = rawData.asInstanceOf[org.apache.spark.sql.DataFrame]
    df.count() shouldBe 2
  }

  it should "fallar si se intenta extraer tipo NO JDBC" in {
    val adapter = new SparkJdbcSourceAdapter(
      spark, container.jdbcUrl, container.jdbcUrl,
      container.username, container.password)

    an[UnsupportedOperationException] should be thrownBy {
      adapter.extract(ReportType.StockActual, Map.empty)
    }
  }
}
```

### Tests de Infraestructura — `SparkMinioParquetAdapter` con Testcontainers MinIO

```scala
// src/test/scala/com/controlstock/reporting/etl/infrastructure/SparkMinioParquetAdapterTest.scala
class SparkMinioParquetAdapterTest extends AnyFlatSpec with Matchers
    with BeforeAndAfterAll with ForAllTestContainer {

  // MinIO via Testcontainers (imagen bitnami/minio)
  override val container: GenericContainer = GenericContainer("bitnami/minio:latest")
    .withEnv("MINIO_ROOT_USER", "minioadmin")
    .withEnv("MINIO_ROOT_PASSWORD", "minioadmin")
    .withExposedPorts(9000)

  private var spark: SparkSession = _

  override def beforeAll(): Unit = {
    super.beforeAll()
    val minioEndpoint = s"http://${container.host}:${container.mappedPort(9000)}"

    spark = SparkSession.builder()
      .appName("MinioParquetTest")
      .master("local[1]")
      .config("spark.hadoop.fs.s3a.endpoint",          minioEndpoint)
      .config("spark.hadoop.fs.s3a.access.key",        "minioadmin")
      .config("spark.hadoop.fs.s3a.secret.key",        "minioadmin")
      .config("spark.hadoop.fs.s3a.path.style.access", "true")
      .config("spark.hadoop.fs.s3a.impl",
        "org.apache.hadoop.fs.s3a.S3AFileSystem")
      .getOrCreate()

    // Crear bucket de prueba
    val s3Client = software.amazon.awssdk.services.s3.S3Client.builder()
      .endpointOverride(java.net.URI.create(minioEndpoint))
      .credentialsProvider(software.amazon.awssdk.auth.credentials
        .StaticCredentialsProvider.create(
          software.amazon.awssdk.auth.credentials
            .AwsBasicCredentials.create("minioadmin", "minioadmin")))
      .region(software.amazon.awssdk.regions.Region.US_EAST_1)
      .build()
    s3Client.createBucket(b => b.bucket("test-reports"))
  }

  override def afterAll(): Unit = {
    spark.stop()
    super.afterAll()
  }

  "SparkMinioParquetAdapter" should "escribir Parquet y el path retornado es correcto" in {
    import spark.implicits._

    val df = Seq(
      ("prod-001", 100L),
      ("prod-002",  50L)
    ).toDF("producto_id", "stock_actual")

    val adapter   = new SparkMinioParquetAdapter(spark, "test-reports")
    val requestId = "req-test-001"
    val path      = adapter.store(df, ReportType.StockActual, requestId)

    // El path debe seguir el formato establecido
    path should startWith("parquet/stock-actual/")
    path should endWith(s"$requestId.parquet")

    // Verificar round-trip: leer el Parquet escrito y verificar datos
    val readBackDf = spark.read.parquet(
      s"s3a://test-reports/$path")

    readBackDf.count() shouldBe 2
    readBackDf.columns should contain allOf ("producto_id", "stock_actual")
  }
}
```

### Tests de Infraestructura — `KafkaEventPublisher` con EmbeddedKafka

```scala
// src/test/scala/com/controlstock/reporting/etl/infrastructure/KafkaEventPublisherTest.scala
class KafkaEventPublisherTest extends AnyFlatSpec with Matchers with EmbeddedKafka {

  "KafkaEventPublisher.publishSuccess" should "publicar ReporteParquetGenerado en el topic correcto" in {
    withRunningKafka {
      val publisher = new KafkaEventPublisher("localhost:6001")

      val event = ReportParquetGenerated(
        requestId   = "req-001",
        reportType  = ReportType.StockActual,
        parquetPath = "parquet/stock-actual/2025/01/req-001.parquet",
        rowCount    = 150L,
        generatedAt = java.time.Instant.now()
      )

      publisher.publishSuccess(event)
      publisher.close()

      // Consumir el mensaje publicado
      val consumed = consumeFirstStringMessageFrom(
        "controlstock.reporting.parquet-generado")

      consumed should include("req-001")
      consumed should include("stock-actual")
      consumed should include("parquet/stock-actual/2025/01/req-001.parquet")
    }
  }

  "KafkaEventPublisher.publishFailure" should "publicar ReporteETLFallido en el topic correcto" in {
    withRunningKafka {
      val publisher = new KafkaEventPublisher("localhost:6001")

      val event = ReportEtlFailed(
        requestId  = "req-002",
        reportType = ReportType.MovimientosPeriodo,
        reason     = "columnas faltantes: cantidad",
        failedAt   = java.time.Instant.now()
      )

      publisher.publishFailure(event)
      publisher.close()

      val consumed = consumeFirstStringMessageFrom(
        "controlstock.reporting.etl-fallido")

      consumed should include("req-002")
      consumed should include("columnas faltantes")
    }
  }
}
```

### Tabla resumen de tests

| Clase | Método / Escenario | Framework | Resultado esperado |
|-------|-------------------|-----------|--------------------|
| `ReportSchemaTest` | `validate` — todas las columnas presentes | ScalaTest | `Right(())` |
| `ReportSchemaTest` | `validate` — columna faltante | ScalaTest | `Left(SchemaValidationError)` con nombre de columna |
| `ReportSchemaTest` | `validate` — tipo incorrecto | ScalaTest | `Left(SchemaValidationError)` con detalle de tipo |
| `ReportTypeTest` | `fromString` — tipo válido | ScalaTest | `Right(ReportType.X)` para los 4 tipos |
| `ReportTypeTest` | `fromString` — tipo desconocido | ScalaTest | `Left(String)` con mensaje descriptivo |
| `ReportTransformerFactoryTest` | `get` — tipo conocido | ScalaTest | Transformer correcto retornado |
| `ReportTransformerFactoryTest` | `getOrFail` — tipo desconocido | ScalaTest | `Left(UnsupportedReportTypeException)` |
| `StockActualTransformerTest` | `transform` — join stock+productos | SparkSession local | DataFrame con columnas correctas, 2 filas |
| `MovimientosPeriodoTransformerTest` | `transform` — filtro por fecha | SparkSession local | Solo movimientos dentro del rango |
| `SparkJdbcSourceAdapterTest` | `extract` — audit_log | Testcontainers PostgreSQL | DataFrame con columnas audit, count=2 |
| `SparkJdbcSourceAdapterTest` | `extract` — tipo no JDBC | Testcontainers PostgreSQL | `UnsupportedOperationException` |
| `SparkMinioParquetAdapterTest` | `store` — round-trip | Testcontainers MinIO | Path correcto; Parquet leído = datos originales |
| `KafkaEventPublisherTest` | `publishSuccess` — evento parquet-generado | EmbeddedKafka | Mensaje consumido con requestId y path |
| `KafkaEventPublisherTest` | `publishFailure` — evento etl-fallido | EmbeddedKafka | Mensaje consumido con requestId y razón de fallo |

### Umbrales de cobertura de código

| Capa | Cobertura mínima | Justificación |
|------|-----------------|---------------|
| Dominio (case classes, traits, validación) | ≥ 85% | Lógica de validación de esquema crítica |
| Aplicación (use cases, factory, transformers) | ≥ 85% | Transformaciones son lógica de negocio central |
| Infraestructura (adapters) | ≥ 80% | Testcontainers cubren caminos principales de I/O |

```bash
# Ejecutar tests con cobertura (scoverage)
sbt coverage test coverageReport

# Ver reporte en target/scala-2.13/scoverage-report/index.html
# Verificar umbrales mínimos
sbt coverageAggregate
```

---

## Criterios de Aceptación

### CA-1: `sbt compile` y `sbt assembly` exitosos

```bash
cd /path/to/report-etl-service

# Compilar
sbt compile
# Debe terminar: [success] Total time: Xs

# Generar fat JAR
sbt assembly
# Debe terminar: [success] Total time: Xs
# Debe generar: target/scala-2.13/report-etl-service-assembly-0.1.0-SNAPSHOT.jar
ls -lh target/scala-2.13/report-etl-service-assembly-*.jar
# Tamaño típico: 200-400 MB (incluye Spark + Mongo Connector)
```

### CA-2: Tests pasan con `sbt test`

```bash
sbt test
# Todos los tests deben pasar:
# [info] ReportSchemaTest:
# [info] - should retornar Right(()) cuando todas las columnas están presentes
# [info] - should retornar Left con columnas faltantes
# [info] - should retornar Left con tipos incorrectos
# [info] ReportTypeTest: ...
# [info] ReportTransformerFactoryTest: ...
# [info] StockActualTransformerTest: ...
# [info] MovimientosPeriodoTransformerTest: ...
# [info] SparkJdbcSourceAdapterTest: ...
# [info] SparkMinioParquetAdapterTest: ...
# [info] KafkaEventPublisherTest: ...
# [info] All tests passed.
```

### CA-3: Validación de esquema fallida publica ReporteETLFallido

```bash
# Corromper temporalmente el catálogo (quitar columna required)
kubectl exec -n databases deploy/postgresql -- psql \
  -U controlstock_reporting -d controlstock_reporting \
  -c "UPDATE report_schema_catalog
      SET column_specs = '[{\"name\":\"columna_inexistente\",\"dataType\":\"StringType\"}]'
      WHERE report_type = 'stock-actual';"

# Ejecutar job manualmente
kubectl create job --from=cronjob/report-etl-service \
  report-etl-fail-test-001 -n apps

# Esperar a que termine
kubectl wait --for=condition=complete --timeout=300s \
  job/report-etl-fail-test-001 -n apps || true

# Verificar que el job terminó (con exit code 0 aunque hubo error — el job maneja el error)
kubectl get job report-etl-fail-test-001 -n apps

# Verificar que el evento de fallo fue publicado en Kafka
kubectl exec -n kafka deploy/kafka -- \
  kafka-console-consumer.sh \
  --bootstrap-server kafka:9092 \
  --topic controlstock.reporting.etl-fallido \
  --from-beginning --max-messages 1
# Debe mostrar JSON con "reason" que incluye "columnas faltantes" o "schema"

# Restaurar el catálogo correcto
kubectl exec -n databases deploy/postgresql -- psql \
  -U controlstock_reporting -d controlstock_reporting \
  -c "-- restaurar column_specs originales para stock-actual ..."
```

### CA-4: Lectura JDBC de audit_log exitosa

```bash
# Ejecutar job con tipo auditoria-operaciones
kubectl create job --from=cronjob/report-etl-service \
  report-etl-audit-test -n apps

# Pasar argumentos específicos (override del command en spec)
kubectl patch job report-etl-audit-test -n apps \
  --type='json' \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"auditoria-operaciones"},
       {"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"req-audit-001"}]'

# O ejecutar con un Job customizado:
kubectl apply -f - <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: report-etl-audit-test
  namespace: apps
spec:
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: report-etl
        image: registry.<VPS_IP>/controlstock/report-etl-service:latest
        command: ["spark-submit", "--master", "local[*]", "--class",
                  "com.controlstock.reporting.etl.EntryPoint",
                  "/app/report-etl-service-assembly.jar",
                  "auditoria-operaciones", "req-audit-test-001"]
        envFrom:
        - secretRef:
            name: report-etl-secrets
EOF

kubectl logs -n apps job/report-etl-audit-test -f
# Debe mostrar: "Parquet almacenado en: parquet/auditoria-operaciones/..."
# Debe mostrar: "ReporteParquetGenerado publicado para requestId=req-audit-test-001"
```

### CA-5: ReporteParquetGenerado publicado por tipo de reporte correcto

```bash
# Verificar evento publicado en Kafka para cada tipo de reporte
kubectl exec -n kafka deploy/kafka -- \
  kafka-console-consumer.sh \
  --bootstrap-server kafka:9092 \
  --topic controlstock.reporting.parquet-generado \
  --from-beginning --max-messages 5 | jq '.'
# Salida esperada (un objeto por tipo procesado):
# {
#   "requestId": "...",
#   "reportType": "stock-actual",
#   "parquetPath": "parquet/stock-actual/2025/01/....parquet",
#   "rowCount": 150,
#   "generatedAt": "2025-01-01T02:05:30Z"
# }

# Verificar archivos Parquet en MinIO
kubectl exec -n minio deploy/minio -- mc ls -r \
  local/controlstock-reports/parquet/
# Debe mostrar archivos .parquet por tipo y fecha
```

### CA-6: CronJob con `concurrencyPolicy: Forbid` — no solapamiento

```bash
# Verificar configuración del CronJob
kubectl get cronjob report-etl-service -n apps -o jsonpath='{.spec.concurrencyPolicy}'
# Esperado: Forbid

# Verificar que si hay un job activo, el siguiente no se lanza
# (simulado manualmente)
kubectl create job --from=cronjob/report-etl-service report-etl-overlap-test1 -n apps
kubectl create job --from=cronjob/report-etl-service report-etl-overlap-test2 -n apps
# El segundo job debe quedar en SUSPENDED o no lanzarse mientras el primero corre
kubectl get jobs -n apps --selector=app=report-etl-service
```

### CA-7: Variables de entorno provienen de Vault (no texto plano)

```bash
# Verificar que los secretos en K8s fueron creados desde Vault
kubectl get secret report-etl-secrets -n apps \
  -o jsonpath='{.data.mongo-uri}' | base64 -d
# Debe mostrar la URI de MongoDB (no vacía, no "test", no "localhost")

# Verificar que los logs del job muestran conexión exitosa a MongoDB
kubectl logs -n apps job/report-etl-manual-* | grep "MongoDB"
# Debe aparecer conexión exitosa, no error de autenticación
```

### CA-8: Formato del path de Parquet en MinIO

```bash
# El path debe seguir EXACTAMENTE el formato:
# parquet/{report_type}/{year}/{month}/{request_id}.parquet

# Verificar con mc (MinIO client)
kubectl exec -n minio deploy/minio -- mc ls -r \
  local/controlstock-reports/parquet/ | head -10
# Ejemplo de salida esperada:
# [2025-01-01] 1.2 MiB parquet/stock-actual/2025/01/req-12345.parquet
# [2025-01-01] 0.8 MiB parquet/movimientos-periodo/2025/01/req-12346.parquet

# Verificar que el evento ReporteParquetGenerado tiene el mismo path
kubectl exec -n kafka deploy/kafka -- \
  kafka-console-consumer.sh \
  --bootstrap-server kafka:9092 \
  --topic controlstock.reporting.parquet-generado \
  --from-beginning --max-messages 1 | python3 -c \
  "import json,sys; d=json.load(sys.stdin); print(d['parquetPath'])"
# Debe coincidir con el path en MinIO
```
