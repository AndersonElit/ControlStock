package com.iamservice.model;

import com.iamservice.model.vo.KeycloakSub;
import reactor.core.publisher.Mono;

public interface KeycloakGateway {
    Mono<KeycloakSub> crearUsuario(String email, String nombre, String password);
    Mono<Void> actualizarUsuario(KeycloakSub sub, String nombre);
    Mono<Void> desactivarUsuario(KeycloakSub sub);
    Mono<Void> asignarRol(KeycloakSub sub, String rolNombre);
    Mono<Void> revocarRol(KeycloakSub sub, String rolNombre);
}
