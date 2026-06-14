package com.example.reportetlservice.domain.ports

/** Puerto de publicación de eventos. Mantiene el dominio libre de Kafka. */
trait EventBusPort {
  def publish(topic: String, key: String, payload: String): Unit
}
