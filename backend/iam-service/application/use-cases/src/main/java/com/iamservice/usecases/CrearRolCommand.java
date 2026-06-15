package com.iamservice.usecases;

public record CrearRolCommand(String nombre, String descripcion) {
    public CrearRolCommand {
        if (nombre == null || nombre.isBlank()) throw new IllegalArgumentException("nombre requerido");
    }
}
