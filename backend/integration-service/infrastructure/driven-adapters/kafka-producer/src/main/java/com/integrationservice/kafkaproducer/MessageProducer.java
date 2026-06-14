package com.integrationservice.kafkaproducer;

import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.stereotype.Component;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

@Component
public class MessageProducer {

    public static final String TOPIC = "messages";

    private final KafkaTemplate<String, Object> kafkaTemplate;

    public MessageProducer(KafkaTemplate<String, Object> kafkaTemplate) {
        this.kafkaTemplate = kafkaTemplate;
    }

    public Mono<Void> send(Object message) {
        return Mono.fromFuture(() -> kafkaTemplate.send(TOPIC, message).toCompletableFuture())
                .subscribeOn(Schedulers.boundedElastic())
                .then();
    }
}
