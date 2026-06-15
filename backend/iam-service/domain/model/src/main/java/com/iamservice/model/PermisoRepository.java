package com.iamservice.model;

import com.iamservice.model.vo.PermisoId;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

public interface PermisoRepository {
    Mono<Permiso> save(Permiso permiso);
    Mono<Permiso> findById(PermisoId id);
    Flux<Permiso> findAll();
    Mono<Boolean> existsByModuloAndOperacion(String modulo, String operacion);
}
