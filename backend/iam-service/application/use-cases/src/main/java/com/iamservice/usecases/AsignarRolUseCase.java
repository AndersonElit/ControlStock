package com.iamservice.usecases;

import com.iamservice.model.*;
import com.iamservice.model.vo.RolId;
import com.iamservice.model.vo.UsuarioId;
import reactor.core.publisher.Mono;

public class AsignarRolUseCase {
    private final UsuarioRepository usuarioRepository;
    private final RolRepository rolRepository;
    private final KeycloakGateway keycloakGateway;

    public AsignarRolUseCase(UsuarioRepository usuarioRepository, RolRepository rolRepository,
                             KeycloakGateway keycloakGateway) {
        this.usuarioRepository = usuarioRepository;
        this.rolRepository = rolRepository;
        this.keycloakGateway = keycloakGateway;
    }

    public Mono<Void> ejecutar(UsuarioId usuarioId, RolId rolId) {
        return Mono.zip(
                usuarioRepository.findById(usuarioId)
                        .switchIfEmpty(Mono.error(new UsuarioNoEncontradoException(usuarioId))),
                rolRepository.findById(rolId)
                        .switchIfEmpty(Mono.error(new RolNoEncontradoException(rolId)))
        ).flatMap(tuple -> {
            Usuario usuario = tuple.getT1();
            Rol rol = tuple.getT2();
            usuario.asignarRol(rolId);
            return keycloakGateway.asignarRol(usuario.getKeycloakSub(), rol.getNombre())
                    .then(usuarioRepository.save(usuario));
        }).then();
    }
}
