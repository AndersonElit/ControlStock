package com.adjustmentservice.outbox;

import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import reactor.core.publisher.Mono;

import java.time.Instant;

/** Relay del outbox: publica periódicamente los eventos PENDING a Kafka y los marca PUBLISHED. */
@Component
public class OutboxRelay {

    private final OutboxRepository repository;
    private final KafkaTemplate<String, String> outboxKafkaTemplate;

    public OutboxRelay(OutboxRepository repository, KafkaTemplate<String, String> outboxKafkaTemplate) {
        this.repository = repository;
        this.outboxKafkaTemplate = outboxKafkaTemplate;
    }

    @Scheduled(fixedDelayString = "${outbox.relay.fixed-delay:5000}")
    public void publishPending() {
        repository.findTop100ByStatusOrderByCreatedAtAsc("PENDING")
                .flatMap(message -> Mono.fromFuture(
                                outboxKafkaTemplate.send(message.getTopic(), message.getAggregateId(), message.getPayload())
                                        .toCompletableFuture())
                        .flatMap(result -> {
                            message.setStatus("PUBLISHED");
                            message.setPublishedAt(Instant.now());
                            return repository.save(message);
                        }))
                .subscribe();
    }
}
