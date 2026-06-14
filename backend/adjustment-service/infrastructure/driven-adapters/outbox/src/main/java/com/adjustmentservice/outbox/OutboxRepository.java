package com.adjustmentservice.outbox;

import org.springframework.data.repository.reactive.ReactiveCrudRepository;
import reactor.core.publisher.Flux;

public interface OutboxRepository extends ReactiveCrudRepository<OutboxMessage, Long> {
    Flux<OutboxMessage> findTop100ByStatusOrderByCreatedAtAsc(String status);
}
