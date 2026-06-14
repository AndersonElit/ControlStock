package com.example.reportetlservice.application.usecases

import com.example.reportetlservice.domain.model.ReportType
import org.apache.spark.sql.DataFrame

/** Contrato común de transformación por tipo de reporte (DR-10). `DataFrame` es el detalle
 *  de la transformación Spark; cada tipo implementa su agregación/pivot/formato lógico. */
trait ReportTransformer {
  def reportType: ReportType
  def transform(raw: DataFrame): DataFrame
}

/** Se lanza cuando el ETL unificado recibe un `reportType` no registrado en la factory. */
class UnsupportedReportTypeException(rt: ReportType)
    extends RuntimeException(s"Unsupported report type: ${rt.value}")
