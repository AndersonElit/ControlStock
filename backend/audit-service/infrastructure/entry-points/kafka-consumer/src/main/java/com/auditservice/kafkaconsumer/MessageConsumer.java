package com.auditservice.kafkaconsumer;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.stereotype.Component;

@Component
public class MessageConsumer {

    private static final Logger log = LoggerFactory.getLogger(MessageConsumer.class);

    @KafkaListener(topics = "messages", groupId = "${spring.kafka.consumer.group-id}")
    public void handleMessage(Object message) {
        log.info("Mensaje recibido: {}", message);
    }
}
