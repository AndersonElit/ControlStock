package com.iamservice.model;

import com.iamservice.model.vo.*;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

public interface UsuarioRepository {
    Mono<Usuario> save(Usuario usuario);
    Mono<Usuario> findById(UsuarioId id);
    Mono<Usuario> findByEmail(Email email);
    Mono<Usuario> findByKeycloakSub(KeycloakSub sub);
    Flux<Usuario> findAll();
    Mono<Boolean> existsByEmail(Email email);
}
