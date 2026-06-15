package com.iamservice.usecases;

import com.iamservice.model.*;
import com.iamservice.model.vo.UsuarioId;
import reactor.core.publisher.Mono;

public class InactivarUsuarioUseCase {
    private final UsuarioRepository usuarioRepository;
    private final KeycloakGateway keycloakGateway;

    public InactivarUsuarioUseCase(UsuarioRepository usuarioRepository, KeycloakGateway keycloakGateway) {
        this.usuarioRepository = usuarioRepository;
        this.keycloakGateway = keycloakGateway;
    }

    public Mono<Void> ejecutar(UsuarioId id) {
        return usuarioRepository.findById(id)
                .switchIfEmpty(Mono.error(new UsuarioNoEncontradoException(id)))
                .flatMap(usuario -> {
                    usuario.inactivar();
                    return keycloakGateway.desactivarUsuario(usuario.getKeycloakSub())
                            .then(usuarioRepository.save(usuario));
                })
                .then();
    }
}
