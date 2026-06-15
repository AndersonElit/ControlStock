package com.iamservice.model;

public enum EstadoUsuario {
    ACTIVO, INACTIVO;

    public static EstadoUsuario fromString(String value) {
        if (value == null) return null;
        for (EstadoUsuario e : values()) {
            if (e.name().equalsIgnoreCase(value)) return e;
        }
        throw new EstadoUsuarioInvalidoException(value);
    }
}
