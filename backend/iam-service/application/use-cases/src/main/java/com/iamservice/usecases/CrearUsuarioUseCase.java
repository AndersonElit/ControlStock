package com.iamservice.usecases;

import com.iamservice.model.*;
import com.iamservice.model.vo.Email;
import com.iamservice.model.vo.UsuarioId;
import reactor.core.publisher.Mono;

public class CrearUsuarioUseCase {
    private final UsuarioRepository usuarioRepository;
    private final KeycloakGateway keycloakGateway;

    public CrearUsuarioUseCase(UsuarioRepository usuarioRepository, KeycloakGateway keycloakGateway) {
        this.usuarioRepository = usuarioRepository;
        this.keycloakGateway = keycloakGateway;
    }

    public Mono<UsuarioDTO> ejecutar(CrearUsuarioCommand command) {
        return usuarioRepository.existsByEmail(new Email(command.email()))
                .flatMap(exists -> {
                    if (exists) return Mono.error(new EmailDuplicadoException(command.email()));
                    return keycloakGateway.crearUsuario(
                            command.email(), command.nombre(), command.passwordTemporal()
                    );
                })
                .flatMap(sub -> {
                    Usuario usuario = Usuario.crear(sub, new Email(command.email()), command.nombre());
                    return usuarioRepository.save(usuario);
                })
                .map(UsuarioMapper::toDTO);
    }
}
