package com.example.reportetlservice.domain.ports

import org.apache.spark.sql.DataFrame

/** Puerto de lectura/escritura de parquet en almacenamiento de objetos (S3). */
trait ParquetStorePort {
  def writeRaw(reportType: String, reportId: String, df: DataFrame): String
  def readRaw(uri: String): DataFrame
  def writeProcessed(reportType: String, reportId: String, df: DataFrame): String
}
