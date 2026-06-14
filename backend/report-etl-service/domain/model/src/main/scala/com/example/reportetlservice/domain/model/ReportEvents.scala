package com.example.reportetlservice.domain.model

/** Eventos de dominio del subsistema de reportería. La serialización vive en infraestructura. */
sealed trait ReportEvent { def reportId: String }

/** Publicado por report-etl-service tras extraer, validar y transformar el DataFrame.
 *  Un evento por formato pedido: el Lambda/OCI-Function Consumer genera exactamente ese archivo. */
final case class ReportParquetGenerated(
    reportId: String,
    runId: String,
    reportType: String,
    parquetUri: String,
    format: String,
    generatedAt: String
) extends ReportEvent

final case class ReportFailed(
    reportId: String,
    stage: String,
    reason: String,
    failedColumns: List[String]
) extends ReportEvent
