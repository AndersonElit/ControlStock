package com.iamservice.usecases;

import java.util.UUID;

public record CrearUsuarioCommand(String email, String nombre, String passwordTemporal) {
    public CrearUsuarioCommand {
        if (email == null || email.isBlank()) throw new IllegalArgumentException("email requerido");
        if (nombre == null || nombre.isBlank()) throw new IllegalArgumentException("nombre requerido");
        if (passwordTemporal == null || passwordTemporal.isBlank()) throw new IllegalArgumentException("password requerido");
    }
}
