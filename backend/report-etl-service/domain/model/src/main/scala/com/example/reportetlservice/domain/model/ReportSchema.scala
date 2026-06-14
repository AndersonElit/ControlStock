package com.example.reportetlservice.domain.model

/** Esquema declarado de un reporte: contrato y fuente de verdad de la validación (DR-1). */
final case class ReportSchema(
    reportType: ReportType,
    version: String,
    columns: List[ColumnSpec],
    integrityRules: List[IntegrityRule]
) {
  def columnNames: Set[String] = columns.map(_.name).toSet
  def notNullColumns: List[String] = columns.filterNot(_.nullable).map(_.name)
}
