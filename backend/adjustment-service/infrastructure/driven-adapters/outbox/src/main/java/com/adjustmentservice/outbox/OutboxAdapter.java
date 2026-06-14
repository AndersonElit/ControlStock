package com.adjustmentservice.outbox;

import com.adjustmentservice.model.OutboxPort;
import org.springframework.stereotype.Component;
import reactor.core.publisher.Mono;

import java.time.Instant;

/** Implementa OutboxPort: escribe el evento en la tabla outbox (misma transacción que el cambio de BD). */
@Component
public class OutboxAdapter implements OutboxPort {

    private final OutboxRepository repository;

    public OutboxAdapter(OutboxRepository repository) {
        this.repository = repository;
    }

    @Override
    public Mono<Void> append(String aggregateType, String aggregateId, String eventType, String topic, String payload) {
        OutboxMessage message = new OutboxMessage();
        message.setAggregateType(aggregateType);
        message.setAggregateId(aggregateId);
        message.setEventType(eventType);
        message.setTopic(topic);
        message.setPayload(payload);
        message.setStatus("PENDING");
        message.setCreatedAt(Instant.now());
        return repository.save(message).then();
    }
}
