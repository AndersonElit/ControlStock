package com.example.reportetlservice.application.usecases

import com.example.reportetlservice.domain.model.ReportType

/** Resuelve el `ReportTransformer` concreto por `ReportType` (patrón Factory, DR-10).
 *  Añadir un tipo nuevo = añadir una clase + registrarla en `BatchMain`; sin tocar el use case. */
class ReportTransformerFactory(registry: Map[ReportType, ReportTransformer]) {
  def resolve(rt: ReportType): ReportTransformer =
    registry.getOrElse(rt, throw new UnsupportedReportTypeException(rt))
}
