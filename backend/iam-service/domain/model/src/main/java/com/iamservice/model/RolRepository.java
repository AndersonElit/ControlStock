package com.iamservice.model;

import com.iamservice.model.vo.RolId;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

public interface RolRepository {
    Mono<Rol> save(Rol rol);
    Mono<Rol> findById(RolId id);
    Mono<Rol> findByNombre(String nombre);
    Flux<Rol> findAll();
    Mono<Boolean> existsByNombre(String nombre);
}
