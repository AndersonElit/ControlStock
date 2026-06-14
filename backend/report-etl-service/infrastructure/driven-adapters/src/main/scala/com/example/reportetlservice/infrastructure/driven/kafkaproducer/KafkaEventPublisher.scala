package com.example.reportetlservice.infrastructure.driven.kafkaproducer

import com.example.reportetlservice.domain.ports.EventBusPort
import org.apache.kafka.clients.producer.{KafkaProducer, ProducerRecord}

import java.util.Properties

/** Publica eventos de dominio (payload JSON) en Kafka. Implementa `EventBusPort`. */
class KafkaEventPublisher(bootstrapServers: String) extends EventBusPort with AutoCloseable {

  private val props = new Properties()
  props.put("bootstrap.servers", bootstrapServers)
  props.put("key.serializer", "org.apache.kafka.common.serialization.StringSerializer")
  props.put("value.serializer", "org.apache.kafka.common.serialization.StringSerializer")
  props.put("acks", "all")

  private val producer = new KafkaProducer[String, String](props)

  override def publish(topic: String, key: String, payload: String): Unit = {
    producer.send(new ProducerRecord[String, String](topic, key, payload)).get()
  }

  override def close(): Unit = producer.close()
}
