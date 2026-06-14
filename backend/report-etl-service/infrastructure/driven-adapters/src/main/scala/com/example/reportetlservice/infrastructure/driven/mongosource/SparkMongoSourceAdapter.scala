package com.example.reportetlservice.infrastructure.driven.mongosource

import com.example.reportetlservice.domain.ports.SourceDataPort
import org.apache.spark.sql.{DataFrame, SparkSession}

/** Lee la colección del read model CQRS (MongoDB) vía mongo-spark-connector (§0, DS-CQRS-3).
 *  Nunca apunta a la BD de escritura (PostgreSQL). */
class SparkMongoSourceAdapter(
    spark: SparkSession,
    uri: String,
    database: String,
    collection: String
) extends SourceDataPort {

  override def read(): DataFrame =
    spark.read
      .format("mongodb")
      .option("connection.uri", uri)
      .option("database", database)
      .option("collection", collection)
      .load()
}
