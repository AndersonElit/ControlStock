package com.adjustmentservice.model;

import reactor.core.publisher.Mono;

/** Puerto secundario de publicación confiable de eventos (Transactional Outbox). */
public interface OutboxPort {
    Mono<Void> append(String aggregateType, String aggregateId, String eventType, String topic, String payload);
}
