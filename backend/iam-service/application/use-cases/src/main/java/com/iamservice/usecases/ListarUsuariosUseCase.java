package com.iamservice.usecases;

import com.iamservice.model.UsuarioRepository;
import reactor.core.publisher.Flux;

public class ListarUsuariosUseCase {
    private final UsuarioRepository usuarioRepository;

    public ListarUsuariosUseCase(UsuarioRepository usuarioRepository) {
        this.usuarioRepository = usuarioRepository;
    }

    public Flux<UsuarioDTO> ejecutar() {
        return usuarioRepository.findAll().map(UsuarioMapper::toDTO);
    }
}
