package com.iamservice.model;

public class UsuarioInactivoException extends RuntimeException {
    public UsuarioInactivoException(Object id) {
        super("El usuario " + id + " está inactivo y no puede recibir roles");
    }
}
