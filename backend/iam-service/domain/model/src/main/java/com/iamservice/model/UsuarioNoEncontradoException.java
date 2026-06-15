package com.iamservice.model;

import com.iamservice.model.vo.UsuarioId;

public class UsuarioNoEncontradoException extends RuntimeException {
    public UsuarioNoEncontradoException(UsuarioId id) {
        super("Usuario no encontrado: " + id.value());
    }
}
