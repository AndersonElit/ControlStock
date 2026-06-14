package com.example.reportetlservice.infrastructure.entrypoints

import com.example.reportetlservice.application.usecases.{ExtractReportUseCase, ReportTransformer, ReportTransformerFactory}
import com.example.reportetlservice.domain.model.{ColumnSpec, ReportSchema, ReportType}
import com.example.reportetlservice.infrastructure.driven.kafkaproducer.KafkaEventPublisher
import com.example.reportetlservice.infrastructure.driven.s3parquet.SparkS3ParquetAdapter
import com.example.reportetlservice.infrastructure.driven.mongosource.SparkMongoSourceAdapter

import org.apache.spark.sql.SparkSession

import java.util.UUID

/** ETL unificado: lee la fuente → valida esquema → transforma (Factory DR-10)
 *  → escribe parquet → publica ReportParquetGenerated (un evento por formato). */
object BatchMain {

  def main(args: Array[String]): Unit = {
    val argMap: Map[String, String] =
      args.grouped(2)
        .collect { case Array(k, v) if k.startsWith("--") => k.stripPrefix("--") -> v }
        .toMap

    val spark = buildSpark()
    try {
      val bucket    = sys.env.getOrElse("REPORT_BUCKET", "reports")
      val bootstrap = sys.env.getOrElse("KAFKA_BOOTSTRAP_SERVERS", "localhost:9092")
      val outTopic  = sys.env.getOrElse("KAFKA_TOPIC_OUT", "controlstock.reporting.parquet-generado")

      val source = new SparkMongoSourceAdapter(
        spark,
        sys.env.getOrElse("MONGO_URI", "mongodb://localhost:27017"),
        sys.env.getOrElse("MONGO_READ_DB", "readmodel"),
        sys.env.getOrElse("MONGO_READ_COLLECTION", "ventas")
      )

      val store  = new SparkS3ParquetAdapter(spark, bucket)
      val events = new KafkaEventPublisher(bootstrap)

      // TODO: registrar transformers (--report-types vacío).
      val registry: Map[ReportType, ReportTransformer] = Map()
      val factory = new ReportTransformerFactory(registry)
      val useCase = new ExtractReportUseCase(source, store, factory, events, outTopic)

      val reportType = ReportType.fromString(argMap.getOrElse("reportType", "default"))
      val reportId   = argMap.getOrElse("reportId", UUID.randomUUID().toString)
      val runId      = UUID.randomUUID().toString
      val formats    = argMap.getOrElse("formats", "csv,xls").split(",").map(_.trim).toList

      // TODO: resolver el ReportSchema vigente desde report_schema_catalog
      //       vía REPORTING_JDBC_URL (tabla <prefix>_reporting.report_schema_catalog).
      val schema = ReportSchema(
        reportType,
        version = "v1",
        columns = List(
          ColumnSpec("id", "string", nullable = false)
          // TODO: declarar las columnas reales del reporte.
        ),
        integrityRules = List.empty
      )

      try {
        useCase.execute(schema, reportType, reportId, runId, formats)
      } finally {
        events.close()
      }
    } finally {
      spark.stop()
    }
  }

  private def buildSpark(): SparkSession = {
    val builder = SparkSession.builder
      .appName("report-etl-service")
      .master(sys.env.getOrElse("SPARK_MASTER", "local[*]"))
    // Almacenamiento de objetos S3-compatible: MinIO en dev (K3s), OCI Object Storage en prod.
    val endpoint = sys.env.getOrElse("STORAGE_ENDPOINT", "")
    val spark = builder.getOrCreate()
    val hc = spark.sparkContext.hadoopConfiguration
    if (endpoint.nonEmpty) hc.set("fs.s3a.endpoint", endpoint)
    hc.set("fs.s3a.path.style.access", "true")
    hc.set("fs.s3a.access.key", sys.env.getOrElse("STORAGE_ACCESS_KEY", "minioadmin"))
    hc.set("fs.s3a.secret.key", sys.env.getOrElse("STORAGE_SECRET_KEY", "changeme_minio"))
    hc.set("fs.s3a.impl", "org.apache.hadoop.fs.s3a.S3AFileSystem")
    spark
  }
}
