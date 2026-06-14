package com.example.reportetlservice.domain.ports

import org.apache.spark.sql.DataFrame

/** Puerto de lectura de la fuente de datos (read model CQRS o JDBC).
 *  `DataFrame` aparece solo como detalle de la transformación tabular en la frontera (DR-10);
 *  los clientes Mongo/JDBC/Spark concretos viven exclusivamente en infraestructura. */
trait SourceDataPort {
  def read(): DataFrame
}
