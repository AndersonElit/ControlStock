package com.iamservice.model;

public class UsuarioYaInactivoException extends RuntimeException {
    public UsuarioYaInactivoException(Object id) {
        super("El usuario " + id + " ya está inactivo");
    }
}
