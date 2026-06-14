package com.inventoryservice.restapi;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;

/**
 * Endpoint de compensación idempotente que el orquestador de saga (integration-service) invoca
 * para revertir un paso. La lógica se implementa bajo TDD; la idempotencia se respalda en la
 * tabla processed_message.
 */
@RestController
@RequestMapping("/saga")
public class CompensationController {

    @PostMapping("/compensar/{sagaId}")
    public Mono<ResponseEntity<Void>> compensar(@PathVariable String sagaId) {
        // TODO (TDD): invocar el caso de uso de compensación; idempotente vía processed_message.
        return Mono.just(ResponseEntity.accepted().build());
    }
}
