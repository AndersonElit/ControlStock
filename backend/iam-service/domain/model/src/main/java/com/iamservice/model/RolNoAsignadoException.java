package com.iamservice.model;

public class RolNoAsignadoException extends RuntimeException {
    public RolNoAsignadoException(Object rolId, Object usuarioId) {
        super("El rol " + rolId + " no está asignado al usuario " + usuarioId);
    }
}
