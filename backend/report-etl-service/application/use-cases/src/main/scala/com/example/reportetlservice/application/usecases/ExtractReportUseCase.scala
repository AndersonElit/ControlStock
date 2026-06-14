package com.example.reportetlservice.application.usecases

import com.example.reportetlservice.domain.model._
import com.example.reportetlservice.domain.ports._
import org.apache.spark.sql.functions.col

/** ETL unificado: lee la fuente, valida el ReportSchema (DR-1), transforma vía Factory (DR-10),
 *  escribe el parquet final y publica ReportParquetGenerated (un evento por formato pedido).
 *  Si la validación falla publica ReportFailed y lanza excepción. */
class ExtractReportUseCase(
    source: SourceDataPort,
    store: ParquetStorePort,
    factory: ReportTransformerFactory,
    events: EventBusPort,
    outTopic: String = "controlstock.reporting.parquet-generado"
) {

  def execute(schema: ReportSchema, reportType: ReportType,
              reportId: String, runId: String, formats: List[String]): Unit = {
    val df = source.read()
    val actual = df.columns.toSet

    val missing = schema.columnNames.diff(actual)
    if (missing.nonEmpty) {
      publishFailed(reportId, "extraction", "missing columns", missing.toList)
      throw new IllegalStateException(s"Schema validation failed: missing columns $missing")
    }

    val nullViolations = schema.notNullColumns.filter { c =>
      actual.contains(c) && df.filter(col(c).isNull).limit(1).count() > 0
    }
    if (nullViolations.nonEmpty) {
      publishFailed(reportId, "extraction", "null values in non-nullable columns", nullViolations)
      throw new IllegalStateException(s"Integrity validation failed: nulls in $nullViolations")
    }

    val transformer = factory.resolve(reportType)
    val transformed = transformer.transform(df)
    val uri         = store.writeProcessed(reportType.value, reportId, transformed)
    val ts          = java.time.Instant.now().toString

    formats.foreach { fmt =>
      val payload =
        s"""{"reportId":"$reportId","runId":"$runId","reportType":"${reportType.value}",""" +
        s""""parquetUri":"$uri","format":"$fmt","generatedAt":"$ts"}"""
      events.publish(outTopic, s"$reportId-$fmt", payload)
    }
  }

  private def publishFailed(reportId: String, stage: String,
                             reason: String, cols: List[String]): Unit = {
    val arr = cols.map(c => "\"" + c + "\"").mkString(",")
    val payload =
      s"""{"reportId":"$reportId","stage":"$stage","reason":"$reason","failedColumns":[$arr]}"""
    events.publish("report.etl.failed", reportId, payload)
  }
}
