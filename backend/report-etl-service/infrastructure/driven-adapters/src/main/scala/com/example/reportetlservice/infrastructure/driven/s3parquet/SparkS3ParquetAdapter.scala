package com.example.reportetlservice.infrastructure.driven.s3parquet

import com.example.reportetlservice.domain.ports.ParquetStorePort
import org.apache.spark.sql.{DataFrame, SaveMode, SparkSession}

/** Lee/escribe parquet en almacenamiento de objetos S3-compatible.
 *  Dev: MinIO en K3s (endpoint via STORAGE_ENDPOINT).
 *  Prod: OCI Object Storage (compatible S3A via endpoint override) o AWS S3.
 *  Idempotente por `reportId` con sobrescritura determinista (DR-3). */
class SparkS3ParquetAdapter(spark: SparkSession, bucket: String) extends ParquetStorePort {

  override def writeRaw(reportType: String, reportId: String, df: DataFrame): String = {
    val uri = s"s3a://$bucket/raw/$reportType/$reportId/"
    df.write.mode(SaveMode.Overwrite).parquet(uri)
    uri
  }

  override def readRaw(uri: String): DataFrame =
    spark.read.parquet(uri)

  override def writeProcessed(reportType: String, reportId: String, df: DataFrame): String = {
    val uri = s"s3a://$bucket/processed/$reportType/$reportId/"
    df.write.mode(SaveMode.Overwrite).parquet(uri)
    uri
  }
}
